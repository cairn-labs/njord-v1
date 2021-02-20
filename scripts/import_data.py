#!/usr/bin/env python3

import ibm_boto3
from ibm_botocore.client import Config, ClientError
import subprocess
import sys
import uuid
import os


# Constants for IBM COS values
COS_ENDPOINT = "https://s3.us-east.cloud-object-storage.appdomain.cloud"
COS_API_KEY_ID = "jmyspJMlV9-3VdxM2lIa_wPLSRSrBQhf2I6036Y77dYm"
COS_INSTANCE_CRN = "crn:v1:bluemix:public:cloud-object-storage:global:a/64fb5a3c3d994473b4ad6ba26bad6327:731f7dc0-5afc-498a-a177-45248f9e2085::"


cos = ibm_boto3.resource("s3",
    ibm_api_key_id=COS_API_KEY_ID,
    ibm_service_instance_id=COS_INSTANCE_CRN,
    config=Config(signature_version="oauth"),
    endpoint_url=COS_ENDPOINT
)

def get_db_config():
    env = os.getenv('MIX_ENV', 'dev')
    if env == 'dev':
        return {
            'user': 'trader_dev',
            'host': 'localhost',
            'password': 'password'
        }
    elif env == 'prod':
        return {
            'user': 'trader_prod',
            'host': 'localhost',
            'password': os.getenv('TRADER_DB_PASSWORD')
        }

def download_large_file(bucket_name, item_name, local_filename):
    print("Starting large file download for {0} from bucket: {1}".format(item_name, bucket_name))

    # set the chunk size to 5 MB
    part_size = 1024 * 1024 * 5

    # set threadhold to 5 MB
    file_threshold = 1024 * 1024 * 5

    # Create client connection
    cos_cli = ibm_boto3.client("s3",
        ibm_api_key_id=COS_API_KEY_ID,
        ibm_service_instance_id=COS_INSTANCE_CRN,
        config=Config(signature_version="oauth"),
        endpoint_url=COS_ENDPOINT
    )

    # set the transfer threshold and chunk size in config settings
    transfer_config = ibm_boto3.s3.transfer.TransferConfig(
        multipart_threshold=file_threshold,
        multipart_chunksize=part_size
    )

    # create transfer manager
    transfer_mgr = ibm_boto3.s3.transfer.TransferManager(cos_cli, config=transfer_config)

    try:
        # initiate file download
        future = transfer_mgr.download(bucket_name, item_name, local_filename)

        # wait for download to complete
        future.result()

        print ("Large file download complete!")
    except Exception as e:
        print("Unable to complete large file download: {0}".format(e))
    finally:
        transfer_mgr.shutdown()


def import_data_slice(filepath):
    db_config = get_db_config()

    subprocess.check_output(f'''PGPASSWORD={db_config['password']} psql -h {db_config['host']} -U {db_config['user']} -c "\copy data(time,data_type,contents,selector,id,price) FROM '{filepath}' WITH DELIMITER ',' CSV HEADER"''', shell=True)


if __name__ == '__main__':
    env, start_date, end_date = sys.argv[1:]
    filename = f"data-{env}-{start_date}-to-{end_date}.csv"
    download_large_file('time-data-slices', filename, f'/tmp/{filename}')
    import_data_slice(f'/tmp/{filename}')
