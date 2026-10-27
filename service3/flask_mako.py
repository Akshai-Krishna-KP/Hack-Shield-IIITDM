"""Small Flask adapter for the Service 3 Mako templates.

This keeps the challenge's Mako rendering path while avoiding the stale
third-party Flask-Mako extension's incompatibility with current Flask and
Werkzeug releases.
"""
from pathlib import Path

from flask import current_app
from mako.lookup import TemplateLookup


class MakoTemplates:
    def __init__(self, app=None):
        if app is not None:
            self.init_app(app)

    def init_app(self, app):
        app.extensions["mako"] = self


def render_template(template_name, **context):
    app = current_app._get_current_object()
    lookup = app.extensions.get("mako_lookup")
    if lookup is None:
        template_dir = Path(app.root_path) / app.template_folder
        lookup = TemplateLookup(directories=[str(template_dir)], input_encoding="utf-8")
        app.extensions["mako_lookup"] = lookup
    return lookup.get_template(template_name).render(**context)
