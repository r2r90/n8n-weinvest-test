# 🏠 n8n Lead Intake Workflow — WeInvest

Workflow n8n simulant la réception et le traitement d'un lead immobilier, avec persistance PostgreSQL et envoi d'email HTML, exécutable en local via Docker.

## Prérequis

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/) (`docker compose` intégré dans Docker Desktop)

## Lancement rapide

```bash
git clone https://github.com/r2r90/we-invest.git
cd we-invest
cp .env.example .env   # remplir les valeurs si nécessaire
docker compose up
```

Trois services démarrent :

| Service      | URL                        | Description                     |
|-------------|----------------------------|---------------------------------|
| **n8n**     | http://localhost:5678      | Éditeur de workflow             |
| **Mailpit** | http://localhost:8025      | Boîte mail de test              |
| **PostgreSQL** | localhost:5432          | Base de données des leads       |

Au premier lancement, n8n demande de créer un compte local (email/mot de passe).

## Configuration

Copier `.env.example` en `.env` et remplir les valeurs :

```env
POSTGRES_USER=weinvest
POSTGRES_PASSWORD=weinvest
POSTGRES_DB=weinvest_db
```

La table `leads` est créée automatiquement au démarrage via `docker/postgres/init.sql`.

## Import du workflow

1. Ouvrir http://localhost:5678
2. Aller dans **Workflows** → **"..."** → **"Import from File"**
3. Sélectionner `workflow.json`
4. Configurer les credentials :

| Credential   | Paramètre          | Valeur                     |
|-------------|---------------------|----------------------------|
| **SMTP**    | Host                | `mailpit`                  |
|             | Port                | `1025`                     |
|             | SSL/TLS             | OFF                        |
|             | Disable STARTTLS    | ON                         |
|             | User / Password     | vide                       |
| **PostgreSQL** | Host             | `postgres`                 |
|             | Port                | `5432`                     |
|             | Database            | valeur de `POSTGRES_DB`    |
|             | User / Password     | valeurs du `.env`          |

5. Cliquer sur **Publish** pour activer le workflow

## Test

### Lead prioritaire (seller)

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "John",
    "lastName": "Doe",
    "email": "john.doe@example.com",
    "source": "website",
    "projectType": "seller",
    "city": "Paris",
    "budget": 450000
  }'
```

### Lead standard (buyer)

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Marie",
    "lastName": "Dupont",
    "email": "marie@example.com",
    "source": "website",
    "projectType": "buyer",
    "city": "Lyon",
    "budget": 200000
  }'
```

### Test avec données manquantes

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "lastName": "Doe",
    "source": "website",
    "budget": 300000
  }'
```

### Vérification

- **Emails** : http://localhost:8025
- **Réponse webhook** : le JSON retourné contient `leadId`, `priority` et `status`
- **Base de données** :
  ```bash
  docker compose exec postgres psql -U weinvest -d weinvest_db -c "SELECT * FROM leads;"
  ```

## Architecture du workflow

```
Webhook Lead Intake (POST /webhook/lead-intake)
    │
    ▼
Validate Required Fields (firstName, email, projectType, city)
    │
    ├── false → Handle Missing Fields → Respond Error
    │           (JSON dynamique avec champs manquants)
    │
    └── true → Enrich Lead Data (leadId, receivedAt, priority, summary)
                    │
                    ▼
              Save Lead to PostgreSQL (INSERT)
                    │
                    ▼
              Check Priority (priority === "high")
                    │
                    ├── true  → Send Priority Email (HTML)
                    │
                    └── false → Send Standard Email (HTML)
                    │
                    ▼
                  Merge
                    │
                    ▼
              Update Email Status (UPDATE email_sent = true)
                    │
                    ▼
              Respond to Webhook (JSON: leadId, priority, status)
```

## Logique métier

**Priorité :**
- `projectType === "seller"` ou `budget > 400 000` → **high**
- Sinon → **normal**

**Validation :**
- Champs obligatoires : `firstName`, `email`, `projectType`, `city`
- En cas d'absence, le workflow retourne une erreur JSON listant dynamiquement les champs manquants

**Email :**
- Format HTML avec mise en forme professionnelle
- Contenu adapté selon la priorité (couleur, libellé)
- Objet : `Hello there !`

## Structure du projet

```
we-invest/
├── compose.yml               # Orchestration Docker (n8n + PostgreSQL + Mailpit)
├── docker/
│   └── postgres/
│       └── init.sql           # Création de la table leads
├── workflow.json              # Workflow n8n exporté
├── .env.example               # Template des variables d'environnement
├── .gitignore
└── README.md
```

## Stack

- **n8n** — orchestration du workflow
- **PostgreSQL 16** — persistance des leads
- **Mailpit** — serveur SMTP local pour les tests
- **Docker Compose** — orchestration des services

