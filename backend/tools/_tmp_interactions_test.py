import requests
url='http://127.0.0.1:8000/interactions/'
print('No auth ->', requests.post(url, json={'track_id':1,'seconds_listened':0,'is_completed':False}).status_code)
print('With fake auth ->', requests.post(url, json={'track_id':1,'seconds_listened':0,'is_completed':False}, headers={'Authorization':'Bearer faketoken'}).status_code)
