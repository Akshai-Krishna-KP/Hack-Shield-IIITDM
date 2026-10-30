#!/usr/bin/env python3
"""Validate game-server service-to-port assignments."""

import re

SERVICE_IDS = set(range(1, 10))
REQUIRED_SERVICE_COUNT = 6
# Every port in this pool must also be forwarded by the QEMU host launcher.
# The game server picks random ports from 5000-5050 (run-hackshield.sh forwards the whole range).
FORWARDED_SERVICE_PORTS = set(range(5000, 5051))


def _service_id(value):
    if isinstance(value, bool):
        raise ValueError("boolean is not a service ID")
    if isinstance(value, int):
        number = value
    elif isinstance(value, str):
        match = re.fullmatch(r"(?:service)?([1-9])", value.strip(), re.IGNORECASE)
        if not match:
            raise ValueError(f"invalid service ID: {value!r}")
        number = int(match.group(1))
    else:
        raise ValueError(f"invalid service ID: {value!r}")
    if number not in SERVICE_IDS:
        raise ValueError(f"service ID must be between 1 and 9: {number}")
    return number


def _port(value):
    if isinstance(value, bool):
        raise ValueError("boolean is not a port")
    if isinstance(value, int):
        number = value
    elif isinstance(value, str) and value.isdecimal():
        number = int(value)
    else:
        raise ValueError(f"invalid port: {value!r}")
    if number not in FORWARDED_SERVICE_PORTS:
        raise ValueError(
            f"port {number} is not in the QEMU-forwarded service port pool"
        )
    return number


def normalize_mapping(response):
    """Return {service_number: port}; accept common response wrapper shapes."""
    if not isinstance(response, dict):
        raise ValueError("game-server response must be a JSON object")

    candidate = None
    for key in ("service_port_mapping", "service_ports", "port_mapping", "mapping"):
        if key in response:
            candidate = response[key]
            break
    if candidate is None and "data" in response and isinstance(response["data"], dict):
        return normalize_mapping(response["data"])
    if candidate is None:
        candidate = response.get("services")
    if candidate is None:
        candidate = response

    pairs = []
    if isinstance(candidate, dict):
        for service, value in candidate.items():
            if isinstance(value, dict):
                value = value.get("port")
            pairs.append((service, value))
    elif isinstance(candidate, list):
        for item in candidate:
            if not isinstance(item, dict):
                raise ValueError("service mapping list entries must be objects")
            service = item.get("service", item.get("service_id", item.get("id")))
            pairs.append((service, item.get("port")))
    else:
        raise ValueError("mapping must be an object or a list of service/port objects")

    mapping = {}
    for service, port in pairs:
        service = _service_id(service)
        if service in mapping:
            raise ValueError(f"service{service} was assigned more than once")
        mapping[service] = _port(port)

    if len(mapping) != REQUIRED_SERVICE_COUNT:
        raise ValueError(
            f"game server must assign exactly six services; received {len(mapping)}"
        )
    if len(set(mapping.values())) != len(mapping):
        raise ValueError("each selected service must receive a unique port")
    return dict(sorted(mapping.items()))
