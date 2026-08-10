# Paseo + Google Antigravity Headless Runner

This repository provides a Dockerfile for deploying a headless VM runner that bridges [Paseo](https://github.com/Jam-fan/paseo) with the Google Antigravity CLI. It allows you to keep an always-on remote agent environment that you can control directly from your mobile device.

## Deployment with Coolify (Using Google AI Pro Subscription)

If you are a Google AI subscriber, you can use your shared Antigravity credit pool by copying your active session credentials from your local machine.

1. On your local machine (where you already use the Antigravity IDE/CLI), open your terminal and run:
   ```bash
   cat ~/.gemini/oauth_creds.json
   ```
2. Copy the entire JSON output.
3. Connect this repository to your machine.
4. Select **Dockerfile** as the build/deploy method.
5. In your Coolify service settings, go to **Environment Variables** and add:
   - `OAUTH_CREDS_JSON`: Paste the JSON output you copied in step 2.
6. **Deploy** the service.

_Note: The container will automatically read this JSON and authenticate your headless CLI agent using your Pro subscription._

## Connecting Your Mobile App

1. Once the container is built and running, open the **Logs** tab for the service in Coolify.
2. The Paseo daemon will output a pairing code (and an ASCII QR code).
3. Open the Paseo app on your mobile device.
4. Scan the QR code or enter the pairing code from the logs to authenticate.
5. Your runner is now paired and ready to execute coding tasks on demand!
