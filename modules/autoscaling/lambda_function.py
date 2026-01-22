import boto3
import os
import logging
import time
from botocore.exceptions import ClientError

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    logger.info(f"Raw event received: {event}")

    try:
        detail_type = event.get('detail-type')
        
        if detail_type == 'Scheduled Event':
            logger.info("Triggered by schedule — taking periodic AMI backups.")
            return handle_scheduled_snapshot()
        
        elif detail_type == 'EC2 Instance State-change Notification':
            detail = event['detail']
            instance_id = detail.get('instance-id')
            state = detail.get('state')

            if not all([instance_id, state]):
                raise ValueError("Missing instance-id or state in event detail")
            
            logger.info(f"Processing instance {instance_id} with state {state}")

            if state == 'running':
                return handle_scheduled_snapshot()
            elif state == 'terminated':
                return handle_terminated(instance_id)
            else:
                logger.info(f"Ignoring state: {state}")
                return respond(200, f"Ignoring state: {state}")
        
        else:
            logger.warning(f"Unknown detail-type: {detail_type}")
            return respond(200, f"Unknown event type: {detail_type}")

    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}", exc_info=True)
        return respond(500, f"Error: {str(e)}")


def wait_for_snapshot_completion(snapshot_id, max_retries=30, delay=10):
    """Wait for snapshot to become available"""
    for attempt in range(max_retries):
        try:
            response = ec2.describe_snapshots(SnapshotIds=[snapshot_id])
            snapshot = response['Snapshots'][0]
            state = snapshot['State']
            
            if state == 'completed':
                return True
            elif state == 'error':
                raise Exception(f"Snapshot {snapshot_id} failed with error state")
                
            logger.info(f"Snapshot {snapshot_id} state: {state} (attempt {attempt + 1}/{max_retries})")
            time.sleep(delay)
            
        except ClientError as e:
            if 'InvalidSnapshot.NotFound' in str(e):
                logger.warning(f"Snapshot {snapshot_id} not found yet, retrying...")
                time.sleep(delay)
                continue
            raise
            
    raise Exception(f"Snapshot {snapshot_id} did not complete within {max_retries * delay} seconds")

def handle_scheduled_snapshot():
    """Create AMIs for all tagged instances every 5 minutes."""
    try:
        # Find all running instances with tag AutoSnapshot=true
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:AutoSnapshot', 'Values': ['true']},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )

        instance_ids = [
            i['InstanceId']
            for r in instances['Reservations']
            for i in r['Instances']
        ]

        if not instance_ids:
            logger.info("No tagged instances found for snapshot.")
            return respond(200, "No instances to snapshot.")

        for instance_id in instance_ids:
            try:
                ami_name = f"AutoBackup-{instance_id}-{int(time.time())}"
                response = ec2.create_image(
                    InstanceId=instance_id,
                    Name=ami_name,
                    Description=f"Scheduled AMI backup of {instance_id}",
                    NoReboot=True
                )
                ami_id = response['ImageId']
                logger.info(f"Created AMI {ami_id} for instance {instance_id}")

                # Tag the AMI
                ec2.create_tags(
                    Resources=[ami_id],
                    Tags=[
                        {'Key': 'OriginalInstance', 'Value': instance_id},
                        {'Key': 'AutoSnapshot', 'Value': 'true'},
                        {'Key': 'CreatedAt', 'Value': str(int(time.time()))}
                    ]
                )
            except Exception as e:
                logger.error(f"Failed to create AMI for {instance_id}: {str(e)}", exc_info=True)

        return respond(200, f"Created AMIs for instances: {instance_ids}")

    except ClientError as e:
        logger.error(f"Error in scheduled snapshot: {str(e)}", exc_info=True)
        raise



def handle_terminated(instance_id):
    """Restore an instance from an AMI backup if no other is running."""
    try:
        # Check if any other AutoSnapshot instance is running or pending
        existing = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:AutoSnapshot', 'Values': ['true']},
                {'Name': 'vpc-id', 'Values': ['vpc-06aaf60a7bd264d05']},
                {'Name': 'instance-state-name', 'Values': ['pending', 'running']}
            ]
        )
        active_instances = [
            i['InstanceId']
            for r in existing['Reservations']
            for i in r['Instances']
        ]

        if active_instances:
            logger.info(f"Active instance(s) already running: {active_instances}. Not launching a new one.")
            return respond(200, f"Instance(s) {active_instances} already running. No new instance launched.")

        # Find the latest AMI
        response = ec2.describe_images(
            Owners=['self'],
            Filters=[
                {'Name': 'tag:OriginalInstance', 'Values': [instance_id]},
                {'Name': 'state', 'Values': ['available']}
            ]
        )
        images = response.get('Images', [])
        if not images:
            raise ValueError(f"No AMI found for instance {instance_id}")

        # Use the most recent AMI
        sorted_images = sorted(images, key=lambda x: x['CreationDate'], reverse=True)
        ami_id = sorted_images[0]['ImageId']
        logger.info(f"Using AMI {ami_id} to restore instance {instance_id}")

        # Read environment variables
        key_name = os.getenv('DEFAULT_KEY_NAME')
        subnet_id = os.getenv('DEFAULT_SUBNET_ID')
        security_groups = os.getenv('DEFAULT_SECURITY_GROUPS', '').split(',')
        instance_type = os.getenv('DEFAULT_INSTANCE_TYPE', 't3.micro')
        default_tag_name = os.getenv('DEFAULT_TAG_NAME', 'ec2-snapshot')

        # Launch a new instance
        new_instance = ec2.run_instances(
            ImageId=ami_id,
            InstanceType=instance_type,
            SubnetId=subnet_id,
            SecurityGroupIds=security_groups,
            KeyName=key_name,
            TagSpecifications=[{
                'ResourceType': 'instance',
                'Tags': [
                    {'Key': 'Name', 'Value': default_tag_name},
                    {'Key': 'RestoredFrom', 'Value': instance_id},
                    {'Key': 'AutoSnapshot', 'Value': 'true'}
                ]
            }],
            MinCount=1,
            MaxCount=1
        )

        new_instance_id = new_instance['Instances'][0]['InstanceId']
        logger.info(f"Launched new instance {new_instance_id} from AMI {ami_id}")

        return respond(200, f"Restored instance {new_instance_id} from AMI {ami_id}")

    except ClientError as e:
        logger.error(f"Error restoring instance: {str(e)}", exc_info=True)
        raise



def resolve_ami_id():
    """Get the latest AMI dynamically"""
    try:
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(
            Name='/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2'
        )
        return response['Parameter']['Value']
    except ClientError as e:
        logger.warning(f"Failed to get latest AMI: {str(e)}. Using fallback.")
        # Fallback to a known recent AMI for us-west-2
        return 'ami-08e3ff0dfac458a93'

def respond(status_code, message):
    return {
        'statusCode': status_code,
        'body': message
    }