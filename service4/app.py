from flask import Flask, jsonify, render_template, request
import os
import requests

app = Flask(__name__)
TIMEOUT = 4

@app.get('/')
def home(): return render_template('index.html')
@app.get('/wiki')
def wiki(): return render_template('wiki.html')
@app.get('/wiki/<slug>')
def article(slug):
    pages = {'incident-response':'incident-response.html','engineering-handbook':'engineering-handbook.html','network-overview':'network-overview.html'}
    template = pages.get(slug)
    if not template: return render_template('404.html'), 404
    return render_template(template)
@app.get('/preview')
def preview_page(): return render_template('preview.html')
@app.get('/directory')
def directory(): return render_template('directory.html')
@app.get('/api/health')
def health(): return jsonify(service='Northstar Knowledge Hub', status='ok')
@app.get('/api/preview')
def preview():
    url = request.args.get('url', '').strip()
    # INTENTIONALLY VULNERABLE FOR THE ISOLATED HACK & SHIELD LAB:
    # This checks only the URL scheme and deliberately does not restrict destination IPs.
    if not (url.startswith('http://') or url.startswith('https://')):
        return jsonify(error='Only http:// and https:// URLs are supported'), 400
    try:
        response = requests.get(url, timeout=TIMEOUT, allow_redirects=True)
    except requests.RequestException as exc:
        return jsonify(error=f'Unable to fetch preview: {exc.__class__.__name__}'), 502
    return jsonify(url=url, status_code=response.status_code, content_type=response.headers.get('Content-Type',''), preview_snippet=response.text[:3000])

if __name__ == '__main__': app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '7007')), debug=False)
