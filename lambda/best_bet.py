import pandas as pd
import numpy
import requests
import base64
import json
import boto3

from datetime import datetime, timedelta, date
from dateutil.parser import parse
from io import StringIO

s3 = boto3.client('s3')
ssm = boto3.client('ssm')      

parameter_name_sportsbook_url = '/alias/tippings/best-bets/sportsbook_url'
parameter_name_last_process_date = '/alias/tippings/best-bets/last-process-date'
parameter_name_s3_bucket_l0 = '/alias/tippings/best-bets/s3_bucket_l0'
parameter_name_s3_bucket_l1 = '/alias/tippings/best-bets/s3_bucket_l1'
parameter_name_kms_key_id = '/alias/tippings/best-bets/kms_key_id'

# LOGGER = logging.getLogger(__name__)
# if os.getenv('DEBUG'):
#     LOGGER.setLevel(logging.DEBUG)
#     LOGGER.debug("*** DEBUGGING ENABLED! ***")
# else:
#     LOGGER.setLevel(logging.INFO)

def ExtractData(base_url, dateString):

    url = base_url + '?' + 'date=' + dateString

    r = requests.get(url)

    if r.ok:

        txt = r.json()

        list_tipping_dt = []
        list_betting_event_id = []
        list_tipster_nm = []
        list_tipster_typ = []
        list_tip_typ = []
        list_sort_val = []
        list_runner_nm = []
        list_runner_num = []
        list_betting_selection_id = []
        list_last_updated_ts = []

        for meeting in txt['meetings']:            

            tipping_dt = meeting['date']

            for event in meeting['events']:

                betting_event_id = event['eventId']

                for tipster in event['tipsters']:

                    tipster_nm = tipster['name']
                    tipster_typ = tipster['type']

                    for tip in tipster['tips']:

                        tip_typ = tip['type']
                        sort_val = tip['sort']
                        runner_nm = tip['name']
                        runner_num = tip['runnerNumber']
                        runner_nm = tip['name']
                        betting_selection_id = tip['outcomeId']            
                        last_updated_ts = datetime.now()

                        list_tipping_dt.append(tipping_dt)
                        list_betting_event_id.append(betting_event_id)
                        list_tipster_nm.append(tipster_nm)
                        list_tipster_typ.append(tipster_typ)
                        list_tip_typ.append(tip_typ)
                        list_sort_val.append(sort_val)
                        list_runner_nm.append(runner_nm)
                        list_runner_num.append(runner_num)
                        list_betting_selection_id.append(betting_selection_id)
                        list_last_updated_ts.append(last_updated_ts)

        # print(txt_parsed)
        tipping = {
            'tipping_dt' : list_tipping_dt,
            'betting_event_id' : list_betting_event_id,
            'tipster_nm' : list_tipster_nm,
            'tipster_typ' : list_tipster_typ,
            'tip_typ' : list_tip_typ,
            'sort_val' : list_sort_val,
            'runner_nm' : list_runner_nm,
            'runner_num' : list_runner_num,
            'betting_selection_id' : list_betting_selection_id,
            'last_updated_ts' : list_last_updated_ts
        }

        df = pd.DataFrame(tipping)

        return df

    else:
        print("HTTP %i - %s, Message %s" % (r.status_code, r.reason, r.text))

def daterange(start_date, end_date):
    for n in range(int ((end_date - start_date).days)):
        yield start_date + timedelta(n)

def getParameterValue(parameter_name):

    parameter = ssm.get_parameter(Name=parameter_name, WithDecryption=False)
    print('Parameter <' + parameter_name + '> Value: ' + parameter['Parameter']['Value'])
    return parameter['Parameter']['Value']

def lambda_handler(event, context):
    """Lambda Handler function"""
    try:  

        last_process_date_string = getParameterValue(parameter_name_last_process_date)
        print('From: ' + last_process_date_string)
        last_process_date = datetime.strptime(last_process_date_string, '%Y-%m-%d')

        s3_bucket_l0 = getParameterValue(parameter_name_s3_bucket_l0)
        s3_bucket_l1 = getParameterValue(parameter_name_s3_bucket_l1)
        sse_kms_key_id = getParameterValue(parameter_name_kms_key_id)
        data_url = getParameterValue(parameter_name_sportsbook_url)

        start_date = last_process_date
        end_date = datetime.now() + timedelta(days=2)

        df = pd.DataFrame()

        for single_date in daterange(start_date, end_date):

            # print(single_date.strftime("%Y-%m-%d"))

            single_date_month = single_date.month
            single_date_day = single_date.day
            single_date_year = single_date.year

            # results = s3.list_objects(Bucket=s3_bucket_l1, Prefix='Contents')
            results = s3.list_objects(Bucket=s3_bucket_l1)
            print("---------------------")
            print(results)
            print("---------------------")

            if('Contents' in results):

                for key in s3.list_objects(Bucket=s3_bucket_l1)['Contents']:      

                    year_str = 'year=' + str(single_date_year)
                    month_str = 'month=' + str(single_date_month)
                    day_str = 'day=' + str(single_date_day)

                    if(year_str in key['Key'] and month_str in key['Key'] and day_str in key['Key']):

                        # print(key['Key'])
                        response = s3.delete_object(
                            Bucket=s3_bucket_l1,
                            Key=key['Key']
                        )
                        print(response)

            file_name_prefix = 'BestBet'
            date_string = single_date.strftime("%Y-%m-%d")
            file_name = file_name_prefix + '_' + date_string + '.csv'

            df = df.append(ExtractData(data_url, date_string), ignore_index=True)

        csv_buffer = StringIO()
        df.to_csv(csv_buffer, index=False)

        from_string = start_date.strftime("%Y-%m-%d")
        to_string = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")

        file_name_prefix = 'BestBet_ProcessedAt_' + (datetime.now()).strftime("%Y%m%d%H%M%S")

        if(from_string == to_string):
            file_name = file_name_prefix + '_' + from_string + '.csv'
        else:
            file_name = file_name_prefix + '_From_' + from_string + '_To_' + to_string + '.csv'

        key='data/date=' + start_date.strftime("%Y-%m-%d") + '/' + file_name

        s3.put_object(
            Body=csv_buffer.getvalue(),
            Bucket=s3_bucket_l0,
            Key=key,
            ServerSideEncryption='aws:kms',
            SSEKMSKeyId=sse_kms_key_id
        )

        end_date_string = end_date.strftime("%Y-%m-%d")

        parameter = ssm.put_parameter(
            Name=parameter_name_last_process_date, 
            Value=end_date_string,
            Type='String',
            Overwrite=True)

        last_process_date_string = getParameterValue(parameter_name_last_process_date)
        print('To: ' + last_process_date_string)

    except Exception as e:
        print(e)
        raise e
