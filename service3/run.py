from application.main import app
import os

app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '1337')), debug=False, use_evalex=False)
