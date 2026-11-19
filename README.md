# calex

calex is a CalDAV and CardDAV server. People sign up, confirm their email, and turn on two-factor authentication in the website. Calendar and address-book clients connect with HTTP Basic using the same email and password. Collections and sharing are created in the web UI and stored in Postgres.

SMTP, registration, and the hostname come from environment variables. calex does not read an INI file, an htpasswd file, or a rights file.

## Environment

| Variable | Purpose |
| --- | --- |
| `HOST` | Public hostname, such as `calex.example.com`. Required outside the test environment. |
| `DATABASE_URL` | Postgres URL. Defaults to `ecto://postgres:postgres@127.0.0.1/calex_dev`. |
| `SECRET_KEY_BASE` | Phoenix secret. Required in production. Generate with `priv/random.sh`. |
| `CLOAK_KEY` | 32 random bytes, base64. Required in production. Generate with `priv/cloak_key.sh`. |
| `REGISTRATION` | `invite` (default) or `public`. The first account is an admin either way. |
| `DISABLE_EMAIL` | `true` or `1` runs without sending mail and confirms accounts immediately. |
| `SMTP_HOST` | SMTP relay. Set together with the username and password, or leave all three unset. |
| `SMTP_PORT` | SMTP port. Defaults to `587`. |
| `SMTP_USERNAME` | SMTP username. |
| `SMTP_PASSWORD` | SMTP password. |
| `SMTP_SSL` | `true` turns on implicit TLS. |
| `EMAIL_FROM` | From address. Defaults to `no-reply@$HOST`. |
| `EMAIL_NAME` | From name. Defaults to `calex`. |
| `PORT` | HTTP port inside the server. Defaults to `4000`. |

A partial SMTP setup refuses to boot unless `DISABLE_EMAIL` is `true` or `1`. In production, leaving `SMTP_HOST`, `SMTP_USERNAME`, and `SMTP_PASSWORD` unset also disables outgoing mail.

## Clients

`/.well-known/caldav` and `/.well-known/carddav` redirect to `/dav/`. A signed-in owner creates calendars and address books in the website, or a client creates them with `MKCALENDAR` and `MKCOL`. Clients put, get, list, and delete events, todos, journals, and vCards. `calendar-query` (including a time range), `calendar-multiget`, `addressbook-query`, `addressbook-multiget`, and `sync-collection` return the stored items. The owner grants another account read, write, or free-busy-only. The next request from that account follows the grant. Free-busy returns busy periods without event details.

## Running

```sh
docker compose -f docker-compose.yml up
```

The image is `shibaobun/calex`. Set `HOST`, `SECRET_KEY_BASE`, and `CLOAK_KEY` before serving it on a public hostname.

## Development

```sh
mix setup
mix phx.server
```

`HOST` must be set. `mix test` uses the test defaults.

## License

The current tree is free software under the GNU Affero General Public License, version 3 or any later version. See `LICENSE.md`.

History through the Radicale commits is GPL-3.0, copyright Kozea and the Radicale contributors. This tree is a clean-room Phoenix rewrite and does not include Radicale's Python. Account, mail, and two-factor behavior follows the AGPL-3.0-or-later apps this project shares that code with. GPLv3 section 13 allows that combination, so the project license is AGPL-3.0-or-later rather than GPL-3.0 only.
