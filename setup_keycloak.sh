#!/bin/bash
echo "Waiting for Keycloak to start (this might take a few seconds)..."
sleep 5

echo "Authenticating to Keycloak as admin..."
docker exec demo_keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password admin

echo "1. Creating Realm 'demo-realm'..."
docker exec demo_keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=demo-realm -s enabled=true || true

echo "2. Creating Client 'client_id_demo'..."
# Create public client with PKCE support and App Link redirect URI
docker exec demo_keycloak /opt/keycloak/bin/kcadm.sh create clients -r demo-realm \
  -s clientId=client_id_demo \
  -s enabled=true \
  -s publicClient=true \
  -s standardFlowEnabled=true \
  -s directAccessGrantsEnabled=true \
  -s 'redirectUris=["clientapp://callback"]' \
  -s 'webOrigins=["+"]' || true

echo "3. Creating User 'admin'..."
docker exec demo_keycloak /opt/keycloak/bin/kcadm.sh create users -r demo-realm \
  -s username=admin \
  -s enabled=true \
  -s email="admin@test.com" || true

echo "4. Setting Password '1234' for User 'admin'..."
docker exec demo_keycloak /opt/keycloak/bin/kcadm.sh set-password -r demo-realm --username admin --new-password 1234 || true

echo "---------------------------------------------------"
echo "✅ Keycloak Setup Complete!"
echo "Realm: demo-realm"
echo "Client ID: client_id_demo"
echo "Test User: admin / 1234"
echo "Admin Console: http://localhost:8080 (admin/admin)"
echo "---------------------------------------------------"
