# PQC Chat App

Minimal chat prototype built with Flutter and Django REST Framework.

Current scope:

- simple login with `name + device identity`
- one shared group chat for all logged-in users
- private chat between any 2 users
- polling-based refresh
- no encryption yet, but client message services are separated for future PQC work

## Backend setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
.venv/bin/python backend/manage.py migrate
.venv/bin/python backend/manage.py runserver
```

Backend API runs locally at `http://127.0.0.1:8000/api`.

## Flutter setup

```bash
flutter pub get
flutter run
```

Notes:

- current default API base URL is `http://91.108.121.56/api`
- login asks only for a name
- the app generates and stores a persistent device identity locally, then reuses it on the same device
- users are not pre-seeded anymore; any new device can join with a new name
- if needed, override it with:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000/api
```

## Tests

```bash
.venv/bin/python backend/manage.py test users chat
flutter test
```
