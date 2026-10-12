#!/usr/bin/env python3
"""Write verified-purchase server configuration; never print credential values."""
import base64
import json
import os
from pathlib import Path
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
import uuid
import jwt


def main():
    environment = os.environ['PURCHASE_ENVIRONMENT']
    if environment not in ('Sandbox', 'Production'):
        raise ValueError('Choose Sandbox for TestFlight or Production for App Store purchases')
    bundle = os.environ['APNS_BUNDLE_ID']
    issuer = os.environ['ASC_ISSUER_ID']
    key_id = os.environ['ASC_KEY_ID']
    body = ''.join(line for line in os.environ['ASC_KEY_P8'].splitlines() if not line.startswith('-----'))
    body = ''.join(body.split())
    base64.b64decode(body, validate=True)
    pem = '-----BEGIN PRIVATE KEY-----\n' + '\n'.join(body[i:i+64] for i in range(0, len(body), 64)) + '\n-----END PRIVATE KEY-----\n'
    token = jwt.encode({'iss': issuer, 'iat': int(time.time()), 'exp': int(time.time()) + 600,
                        'aud': 'appstoreconnect-v1'}, pem, algorithm='ES256', headers={'kid': key_id, 'typ': 'JWT'})
    url = 'https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=' + urllib.parse.quote(bundle, safe='')
    request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
    apps = json.load(urllib.request.urlopen(request, timeout=30))['data']
    exact = [a for a in apps if a['attributes']['bundleId'] == bundle]
    if len(exact) != 1:
        raise ValueError('App Store Connect must contain exactly one matching app')
    root = urllib.request.urlopen('https://www.apple.com/certificateauthority/AppleRootCA-G3.cer', timeout=30).read()
    # Refuse an HTML error page or a non-certificate response.
    from cryptography import x509
    certificate = x509.load_der_x509_certificate(root)
    if certificate.subject != certificate.issuer or not certificate.extensions.get_extension_for_class(x509.BasicConstraints).value.ca:
        raise ValueError('Apple trust root is not a root CA')
    # App Store Connect keys authorize metadata/upload operations only. Apple's
    # transaction API requires the separately generated In-App Purchase key.
    iap_id = os.environ.get('IAP_KEY_ID', '')
    iap_issuer = os.environ.get('IAP_ISSUER_ID', '')
    iap_raw = os.environ.get('IAP_KEY_P8', '')
    iap_pem = ''
    if iap_id and iap_issuer and iap_raw:
        iap_body = ''.join(line for line in iap_raw.splitlines() if not line.startswith('-----'))
        iap_body = ''.join(iap_body.split())
        base64.b64decode(iap_body, validate=True)
        iap_pem = '-----BEGIN PRIVATE KEY-----\n' + '\n'.join(iap_body[i:i+64] for i in range(0, len(iap_body), 64)) + '\n-----END PRIVATE KEY-----\n'
        iap_token = jwt.encode({'iss': iap_issuer, 'iat': int(time.time()),
            'exp': int(time.time()) + 600, 'aud': 'appstoreconnect-v1', 'bid': bundle},
            iap_pem, algorithm='ES256', headers={'kid': iap_id, 'typ': 'JWT'})
        host = 'api.storekit-sandbox.itunes.apple.com' if environment == 'Sandbox' else 'api.storekit.itunes.apple.com'
        # Read a nonexistent test-notification status (token shaped like Apple's,
        # "<uuid>_<milliseconds>"). This sends nothing and changes no transaction.
        # Only 401/403 mean the key was refused; 400/404 come after authentication.
        token_id = str(uuid.uuid4()) + '_' + str(int(time.time() * 1000))
        probe = urllib.request.Request('https://' + host + '/inApps/v1/notifications/test/' + token_id,
            headers={'Authorization': 'Bearer ' + iap_token})
        try:
            urllib.request.urlopen(probe, timeout=30).close()
            print('In-App Purchase key authenticated with Apple transaction API.')
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise ValueError('App Store Server API key check failed (HTTP ' + str(error.code) + ')') from None
            if error.code in (400, 404):
                print('In-App Purchase key authenticated with Apple transaction API.')
            else:
                print('::warning::Apple answered HTTP ' + str(error.code) + '; the In-App Purchase key could not be confirmed now.')
    else:
        iap_id = iap_issuer = ''
        print('::warning::In-App Purchase key is missing. Unlimited Super Psst verification stays unavailable; the daily free allowance works.')
    values = {'APP_STORE_ENVIRONMENT': environment, 'APP_STORE_BUNDLE_ID': bundle,
              'APP_STORE_APP_ID': exact[0]['id'], 'APP_STORE_ISSUER_ID': iap_issuer,
              'APP_STORE_KEY_ID': iap_id, 'APP_STORE_PRIVATE_KEY': iap_pem,
              'APPLE_ROOT_CA_BASE64': json.dumps([base64.b64encode(root).decode()])}
    path = Path(sys.argv[1])
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        for name, value in values.items():
            if value == '':
                continue
            output.write(name + '=' + json.dumps(value) + '\n')
    print('Purchase verification configuration prepared for ' + environment + '; credentials not printed.')


if __name__ == '__main__':
    main()
