#!/usr/bin/env python

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import logging
import os
from typing import Dict, Any
import urllib.error
import urllib.request


class MCRouterRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, request, client_address, server):
        super().__init__(request, client_address, server)

    def __get_webhook_url(self) -> str:
        webhook_url = os.getenv("DISCORD_WEBHOOK_URL")
        if not webhook_url:
            raise ValueError(
                "Environment variable DISCORD_WEBHOOK_URL is not set")
        return webhook_url

    def __send_simple_response(self, status_code: int):
        self.send_response(status_code)
        self.end_headers()

    def __exception_response(self, status_code: int, message: str):
        logging.exception(message)
        self.__send_simple_response(status_code)

    def __error_response(self, status_code: int, message: str):
        logging.error(message)
        self.__send_simple_response(status_code)

    def do_GET(self):
        self.__send_simple_response(200)

    def do_POST(self):
        # Only respond to the /webhook path
        if self.path != "/webhook":
            self.send_response(404)
            self.end_headers()
            return

        # Decode the payload
        event_payload: Dict[str, Any]
        try:
            event_payload = json.loads(self.rfile.read(
                int(self.headers.get('Content-Length', 0))))
        except Exception:
            return self.__exception_response(400, "Invalid JSON payload")

        # Ignore everything but connect and disconnect events
        event = event_payload.get("event")
        if not event:
            return self.__error_response(400, "No event found in payload")

        if event != "connect" and event != "disconnect":
            return self.__send_simple_response(200)

        # Only respond to successful connections
        status = event_payload.get("status")
        if not status or not isinstance(status, str):
            return self.__error_response(400, "Invalid or missing status")
        if status != "success":
            return self.__send_simple_response(200)

        # Get the player name
        player = event_payload.get("player")
        if not player:
            return self.__error_response(400, "No player data found in payload")

        player_name = player.get("name")
        if not player_name or not isinstance(player_name, str):
            return self.__error_response(400, "Invalid or missing player name")

        # Get the server name
        server = event_payload.get("server")
        if not server:
            return self.__error_response(400, "No server data found in payload")

        # Get the webhook URL
        webhook_url: str
        try:
            webhook_url = self.__get_webhook_url()
        except Exception:
            return self.__error_response(500, "Failed to get the webhook URL")

        # Send the message to send to Discord
        # TODO @ roles
        payload = {
            "content": f"Player **{player_name}** has {event}ed to the server **{server}**.",
        }

        request = urllib.request.Request(
            webhook_url,
            data=json.dumps(payload).encode(),
            headers={
                'Content-Type': 'application/json; charset=UTF-8',
                "User-Agent": "MCRouterDiscordWebhook/1.0"
            },
            method='POST'
        )

        try:
            with urllib.request.urlopen(request):
                pass
        except urllib.error.HTTPError as e:
            return self.__error_response(500, f"Failed to send message to Discord with a {e.code} {e.reason} response: {e.fp.read().decode()}")
        except:
            return self.__exception_response(500, f"Failed to send message to Discord:")

        # Everything completed successfully - send a 200 OK response
        self.__send_simple_response(200)


if __name__ == '__main__':
    HTTPServer(("", 80), MCRouterRequestHandler).serve_forever()
