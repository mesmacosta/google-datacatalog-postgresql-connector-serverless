"""Cloud Function for handling PostgreSQL metadata sync.

"""

import logging
import os

from google.cloud import secretmanager
from google.datacatalog_connectors.postgresql import \
    datacatalog_cli

def sync(event, context):
    """Sync PostgreSQL metadata with Google Data Catalog

    """

    try:
        # Log out the message that triggered the function
        logging.info('This Function was triggered by messageId {} published at {}'.
                     format(context.event_id, context.timestamp))

        logging.info('Starting sync logic.')
        datacatalog_cli.PostgreSQL2DatacatalogCli().run(_get_connector_run_args())
        logging.info('Sync execution done.')
        return 'ok', 200
    except PermissionError as err:
        logging.error('Error executing sync: %s', str(err))
        return 'authentication denied', 401
    except UserWarning as warn:
        logging.error('Error executing sync: %s', str(warn))
        return str(warn), 400
    except Exception as err:
        logging.error('Error executing sync: %s', str(err))
        return 'failed to sync', 500


def _get_connector_run_args():
    db_crendetials = _get_db_credentials()

    return [
        '--datacatalog-project-id', os.environ.get('DATACATALOG_PROJECT_ID'),
        '--datacatalog-location-id', os.environ.get('DATACATALOG_LOCATION_ID'),
        '--postgresql-host', os.environ.get('POSTGRESQL_SERVER'),
        '--postgresql-user', db_crendetials['user'],
        '--postgresql-pass', db_crendetials['pass'],
        '--postgresql-database', os.environ.get('POSTGRES_DB')
    ]


def _get_db_credentials():
    return {'user': _get_secrets_manager_property(os.environ.get('DB_CREDENTIALS_USER_SECRET')),
            'pass': _get_secrets_manager_property(os.environ.get('DB_CREDENTIALS_PASS_SECRET'))}


def _get_secrets_manager_property(property_name):
    client = secretmanager.SecretManagerServiceClient()
    project_number = os.environ.get('DATACATALOG_PROJECT_NUMBER')

    resource_name = 'projects/{}/secrets/{}/versions/1'.format(
        project_number, property_name)
    response = client.access_secret_version(resource_name)
    return response.payload.data.decode('UTF-8')

