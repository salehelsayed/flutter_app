 Migrate mknoun.xyz from GoDaddy to Cloudflare

  Current DNS records to migrate

  ┌───────┬────────────┬─────────────┐
  │ Type  │    Name    │    Value    │
  ├───────┼────────────┼─────────────┤
  │ A     │ mknoun.xyz │ 13.60.15.36 │
  ├───────┼────────────┼─────────────┤
  │ CNAME │ www        │ mknoun.xyz  │
  └───────┴────────────┴─────────────┘

  No MX, TXT, or AAAA records.

  ---
  Step 1: Create Cloudflare account

  1. Go to dash.cloudflare.com and sign up (free)
  2. Click "Add a site"
  3. Enter mknoun.xyz
  4. Select the Free plan
  5. Cloudflare will scan your DNS — verify it found the two records above
  6. For both records, set the proxy toggle to DNS only (gray cloud)
  7. Click Continue
  8. Cloudflare gives you two nameservers — write them down, e.g.:
  ada.ns.cloudflare.com
  bob.ns.cloudflare.com

  Step 2: Update nameservers at GoDaddy

  1. Log in to GoDaddy → My Products → click DNS next to mknoun.xyz
  2. Scroll to Nameservers → click Change
  3. Select "I'll use my own nameservers"
  4. Replace the GoDaddy nameservers with the two Cloudflare ones
  5. Save

  Step 3: Wait for propagation

  Check propagation status:
  dig mknoun.xyz NS +short

  When it returns the Cloudflare nameservers instead of domaincontrol.com, you're good. Usually takes 10 minutes to a few hours. Cloudflare will also email you when it's active.

  Step 4: Create a Cloudflare API token

  1. Cloudflare dashboard → click your profile icon (top right) → My Profile
  2. Go to API Tokens tab → Create Token
  3. Use the template "Edit zone DNS"
  4. Under Zone Resources, select Specific zone → mknoun.xyz
  5. Click Continue to summary → Create Token
  6. Copy the token — you'll only see it once

  Step 5: Install certbot Cloudflare plugin on the server

  ssh -i se.pem ubuntu@13.60.15.36

  sudo apt update
  sudo apt install python3-certbot-dns-cloudflare -y

  Step 6: Store the API token on the server

  sudo tee /etc/cloudflare.ini <<EOF
  dns_cloudflare_api_token = YOUR_TOKEN_HERE
  EOF
  sudo chmod 600 /etc/cloudflare.ini

  Step 7: Issue the wildcard certificate

  sudo certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/cloudflare.ini \
    -d "mknoun.xyz" \
    -d "*.mknoun.xyz" \
    --agree-tos \
    -m your-email@example.com

  Certbot will automatically create a _acme-challenge TXT record via the Cloudflare API, verify it, and issue the cert.

  Step 8: Update nginx to use the new cert

  The new cert may be stored under a different path (e.g. /etc/letsencrypt/live/mknoun.xyz-0001/). Check:

  sudo ls /etc/letsencrypt/live/

  If it created a new directory, update nginx:
  sudo nano /etc/nginx/sites-available/mknoun.xyz

  Update all ssl_certificate and ssl_certificate_key paths to point to the new wildcard cert, then:

  sudo nginx -t && sudo nginx -s reload

  Step 9: Remove the old HTTP-01 cert (optional cleanup)

  sudo certbot delete --cert-name mknoun.xyz

  Only do this if the wildcard cert was issued under a different name (like mknoun.xyz-0001). If it replaced the original, skip this.

  Step 10: Verify auto-renewal works

  sudo certbot renew --dry-run

  Should show success using the dns-cloudflare authenticator.

  Step 11: Verify everything works

  # Check the cert being served
  openssl s_client -connect mknoun.xyz:443 -servername mknoun.xyz </dev/null 2>/dev/null | openssl x509 -noout -text | grep -E "Subject:|DNS:"

  # Should show:
  #   Subject: CN = mknoun.xyz
  #   DNS:mknoun.xyz, DNS:*.mknoun.xyz

  # Check WSS port too
  openssl s_client -connect mknoun.xyz:4001 -servername mknoun.xyz </dev/null 2>/dev/null | openssl x509 -noout -text | grep "DNS:"

  ---
  After migration: Adding a new relay node

  Once Cloudflare is set up, adding a new node is just:

  1. Cloudflare dashboard → DNS → Add record: A | relay2 | <new-IP> | DNS only
  2. Copy the wildcard cert to the new instance
  3. Deploy nginx + relay-server with a new private key
  4. Update your app with the new multiaddr

  ---
  Checklist

  - Create Cloudflare account, add mknoun.xyz
  - Update nameservers at GoDaddy
  - Wait for propagation (check with dig)
  - Create Cloudflare API token (Edit zone DNS)
  - Install python3-certbot-dns-cloudflare on server
  - Store token in /etc/cloudflare.ini
  - Issue wildcard cert with certbot --dns-cloudflare
  - Update nginx cert paths if needed
  - Test with certbot renew --dry-run
  - Verify cert shows *.mknoun.xyz in browser/openssl

  Want me to help execute any of these steps?