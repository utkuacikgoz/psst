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
    values = {'APP_STORE_ENVIRONMENT': environment, 'APP_STORE_BUNDLE_ID': bundle,
              'APP_STORE_APP_ID': exact[0]['id'], 'APP_STORE_ISSUER_ID': issuer,
              'APP_STORE_KEY_ID': key_id, 'APP_STORE_PRIVATE_KEY': pem,
              'APPLE_ROOT_CA_BASE64': json.dumps([base64.b64encode(root).decode()])}
    path = Path(sys.argv[1])
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        for name, value in values.items():
            output.write(name + '=' + json.dumps(value) + '\n')
    print('Purchase verification configuration prepared for ' + environment + '; credentials not printed.')


if __name__ == '__main__':
    main()
