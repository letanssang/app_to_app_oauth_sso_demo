import http.server
import socketserver
import json
import urllib.parse
import urllib.request
import urllib.error
import uuid
import hashlib
import base64

PORT = 8081
KEYCLOAK_TOKEN_URL = "http://localhost:8080/realms/demo-realm/protocol/openid-connect/token"

# In-memory storage to map our short-lived authorization codes to actual Keycloak Tokens and PKCE data
# Format: { "auth_code_uuid": { "tokens": { ...keycloak_token_response }, "code_challenge": "..." } }
AUTH_CODES: dict[str, dict] = {}

def base64url_encode(data: bytes) -> str:
    """Helper to perform base64url encoding without padding as required by PKCE."""
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

class BackendProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = urllib.parse.parse_qs(post_data)

        if self.path == '/login':
            print(f"\n[Backend] Received Login Request from Auth Provider App (App B)")
            username = params.get('username', [''])[0]
            password = params.get('password', [''])[0]
            # Capture the code_challenge passed from App B (which got it from App A)
            code_challenge = params.get('code_challenge', [''])[0]
            
            # Exchange with Keycloak using Direct Access Grant (ROPC)
            keycloak_data = urllib.parse.urlencode({
                'client_id': 'client_id_demo',
                'username': username,
                'password': password,
                'grant_type': 'password'
            }).encode('utf-8')
            
            req = urllib.request.Request(KEYCLOAK_TOKEN_URL, data=keycloak_data)
            req.add_header('Content-Type', 'application/x-www-form-urlencoded')
            
            try:
                with urllib.request.urlopen(req) as response:
                    keycloak_response = json.loads(response.read().decode('utf-8'))
                    print(f"[Backend] ✅ Keycloak Login Success for user: {username}")
                    
                    # Generate a secure short-lived authorization code
                    auth_code = str(uuid.uuid4())
                    
                    # Cache the Keycloak tokens AND the code_challenge
                    AUTH_CODES[auth_code] = {
                        "tokens": keycloak_response,
                        "code_challenge": code_challenge
                    }
                    
                    # Return ONLY the short-lived code to App B
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"code": auth_code}).encode('utf-8'))
                    
            except urllib.error.HTTPError as e:
                print(f"[Backend] ❌ Keycloak Login Failed: {e.code}")
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(e.read())
            except urllib.error.URLError as e:
                print(f"[Backend] ❌ Failed to communicate with Keycloak: {e}")
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "server_error"}).encode('utf-8'))

        elif self.path == '/token':
            print(f"\n[Backend] Received Token Request from Client App (App A)")
            
            # Extract the code and verifier received from Client App
            code = params.get('code', [''])[0]
            code_verifier = params.get('code_verifier', [''])[0]
            
            if code not in AUTH_CODES:
                print(f"[Backend] ❌ Invalid or Expired Authorization Code: {code}")
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "invalid_grant"}).encode('utf-8'))
                return
                
            # --- PKCE VERIFICATION STEP ---
            session_data = AUTH_CODES[code]
            stored_challenge = session_data.get("code_challenge")
            
            if stored_challenge:
                # Calculate the S256 hash of the provided verifier
                calculated_hash = hashlib.sha256(code_verifier.encode('ascii')).digest()
                calculated_challenge = base64url_encode(calculated_hash)
                
                if calculated_challenge != stored_challenge:
                    print(f"[Backend] ❌ PKCE Verification Failed!")
                    print(f"            Expected: {stored_challenge}")
                    print(f"            Got:      {calculated_challenge}")
                    # Delete the compromised code immediately
                    del AUTH_CODES[code]
                    self.send_response(400)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": "invalid_grant", "error_description": "PKCE verification failed"}).encode('utf-8'))
                    return
                print(f"[Backend] 🔒 PKCE Verification Passed!")
            else:
                print(f"[Backend] ⚠️ No PKCE challenge stored for this code. Proceeding without verification.")
            
            print(f"[Backend] ✅ Authorization Code valid. Exchanging for cached Keycloak Tokens...")
            
            # Retrieve cached tokens and DELETE them (One-time use only!)
            keycloak_tokens = AUTH_CODES.pop(code)["tokens"]
            
            # Return the Keycloak tokens back to the Client App
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(keycloak_tokens).encode('utf-8'))
            print(f"[Backend] ✅ Auth Flow Successfully Completed!")

        else:
            self.send_response(404)
            self.end_headers()

socketserver.TCPServer.allow_reuse_address = True

with socketserver.TCPServer(("", PORT), BackendProxyHandler) as httpd:
    print(f"🚀 Backend Proxy Server is running at http://0.0.0.0:{PORT}")
    print("Listening for Requests...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")
        httpd.server_close()
