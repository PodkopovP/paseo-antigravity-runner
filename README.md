# Paseo + Google Antigravity Headless Runner

This repository provides a Dockerfile for deploying a headless VM runner that bridges [Paseo](https://github.com/Jam-fan/paseo) with the Google Antigravity CLI. It allows you to keep an always-on remote agent environment that you can control directly from your mobile device.

## Deployment with Coolify

1. Connect this repository to your Coolify instance.
2. Select **Dockerfile** as the build/deploy method.
3. In your Coolify service settings, set the following environment variables:
   - `GOOGLE_API_KEY`: Your API key for Google Antigravity (obtainable from [Google AI Studio](https://aistudio.google.com/)).
4. **Deploy** the service.

## Connecting Your Mobile App

1. Once the container is built and running, open the **Logs** tab for the service in Coolify.
2. The Paseo daemon will output a pairing code (and an ASCII QR code).
3. Open the Paseo app on your mobile device.
4. Scan the QR code or enter the pairing code from the logs to authenticate.
5. Your runner is now paired and ready to execute coding tasks on demand!
