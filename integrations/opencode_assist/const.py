"""Constants for the OpenCode Assist integration."""

from __future__ import annotations

DOMAIN = "opencode_assist"
TITLE = "OpenCode Assist"

CONF_HOST = "host"
CONF_PORT = "port"
CONF_PASSWORD = "password"
CONF_AGENT = "agent"
CONF_DIRECTORY = "directory"
CONF_ALLOWED_USERS = "allowed_users"
CONF_PROMPT_TIMEOUT = "prompt_timeout"

DEFAULT_HOST = "7d771edf-opencode-vscode"
DEFAULT_PORT = 4096
DEFAULT_AGENT = "assist"
DEFAULT_DIRECTORY = "/share/opencode"
DEFAULT_PROMPT_TIMEOUT = 60

SESSION_TTL = 6 * 60 * 60
MIN_PROMPT_TIMEOUT = 5
MAX_PROMPT_TIMEOUT = 300
