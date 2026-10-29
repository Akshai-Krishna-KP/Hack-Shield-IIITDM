from pathlib import Path
from flask import Flask, jsonify
app = Flask(__name__)
FLAG_PATH = Path('/opt/flags/flag4')
ASSETS = [
    {'id': 101, 'name': 'Rack Switch - Core-A', 'location': 'DC1-R04', 'owner': 'IT Operations'},
    {'id': 102, 'name': 'Fleet Laptop - ENG-22', 'location': 'Engineering', 'owner': 'Workplace IT'},
    {'id': 103, 'name': 'Backup NAS - Archive', 'location': 'DC1-R09', 'owner': 'Infrastructure'},
]
@app.get('/internal/health')
def health(): return jsonify(service='Fleet Inventory API', status='ok', version='1.4.2')
@app.get('/internal/assets')
def assets(): return jsonify(service='Fleet Inventory API', assets=ASSETS)
@app.get('/internal/assets/<int:asset_id>')
def asset_detail(asset_id):
    item = next((a for a in ASSETS if a['id'] == asset_id), None)
    return (jsonify(item), 200) if item else (jsonify(error='Asset not found'), 404)
@app.get('/internal/admin/flag')
def admin_flag():
    # INTENTIONALLY UNAUTHENTICATED for the isolated SSRF exercise.
    try: flag = FLAG_PATH.read_text(encoding='utf-8').strip()
    except OSError: flag = '(flag file unreadable)'
    return jsonify(service='Fleet Inventory API', notice='Internal administrative endpoint', flag=flag)
if __name__ == '__main__': app.run(host='127.0.0.1', port=7108, debug=False)
