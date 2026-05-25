# n8n Lead Intake Workflow — WeInvest

Workflow n8n simulant la réception et le traitement d'un lead immobilier, avec persistance PostgreSQL et envoi d'email HTML, exécutable en local via Docker.

## Stack

| Outil | Version | Rôle |
|---|---|---|
| **n8n** | latest | Orchestration du workflow |
| **PostgreSQL** | 16 | Persistance des leads |
| **Mailpit** | latest | Serveur SMTP local (tests) |
| **Docker Compose** | v2+ | Orchestration des services |

---

## Prérequis

- [Docker](https://docs.docker.com/get-docker/) avec Docker Compose v2 intégré

---

## Démarrage

```bash
git clone https://github.com/r2r90/we-invest.git
cd we-invest
cp .env.example .env
docker compose up
```

Au premier lancement, n8n demande de créer un compte local (email / mot de passe quelconques).

### Services disponibles

| Service | URL / Adresse | Description |
|---|---|---|
| **n8n** | http://localhost:5678 | Éditeur de workflow |
| **Mailpit** | http://localhost:8025 | Interface webmail de test |
| **PostgreSQL** | `localhost:5432` | Base de données des leads |

---

## Configuration

### Variables d'environnement

Copier `.env.example` en `.env` et ajuster si besoin :

```env
POSTGRES_USER=root
POSTGRES_PASSWORD=root
POSTGRES_DB=weinvest_db
```

Ces variables sont lues par le service `postgres` dans `compose.yml`.

---

## Base de données PostgreSQL

### Connexion

| Paramètre | Valeur |
|---|---|
| Host | `localhost` |
| Port | `5432` |
| Database | `weinvest_db` (valeur de `POSTGRES_DB`) |
| User | `root` (valeur de `POSTGRES_USER`) |
| Password | `root` (valeur de `POSTGRES_PASSWORD`) |

> Depuis un autre conteneur Docker (ex: n8n), utiliser `postgres` comme host à la place de `localhost`.

### Schéma de la table `leads`

La table est créée automatiquement au premier démarrage via `docker/postgres/init.sql`.

```sql
CREATE TABLE IF NOT EXISTS leads (
  id             SERIAL PRIMARY KEY,
  lead_id        VARCHAR(100) UNIQUE NOT NULL,
  first_name     VARCHAR(100),
  last_name      VARCHAR(100),
  email          VARCHAR(255),
  city           VARCHAR(100),
  project_type   VARCHAR(100),
  budget         INTEGER,
  priority       VARCHAR(50),
  source         VARCHAR(100),
  received_at    TIMESTAMP,
  email_sent     BOOLEAN DEFAULT FALSE,
  email_sent_at  TIMESTAMP,
  created_at     TIMESTAMP DEFAULT NOW()
);
```

### Requêtes utiles

```bash
# Connexion interactive
docker compose exec postgres psql -U root -d weinvest_db

# Lister tous les leads
docker compose exec postgres psql -U root -d weinvest_db -c "SELECT * FROM leads;"

# Leads prioritaires uniquement
docker compose exec postgres psql -U root -d weinvest_db -c "SELECT * FROM leads WHERE priority = 'high';"

# Vérifier les emails envoyés
docker compose exec postgres psql -U root -d weinvest_db -c "SELECT lead_id, email, email_sent, email_sent_at FROM leads;"

# Vider la table (reset)
docker compose exec postgres psql -U root -d weinvest_db -c "TRUNCATE TABLE leads RESTART IDENTITY;"
```

---

## Import du workflow n8n

1. Ouvrir http://localhost:5678
2. Aller dans **Workflows** → menu **"..."** → **"Import from File"**
3. Sélectionner `workflow.json`
4. Configurer les credentials ci-dessous
5. Cliquer sur **Publish** pour activer le workflow

### Credentials à configurer

**SMTP (Mailpit)**

| Paramètre | Valeur |
|---|---|
| Host | `mailpit` |
| Port | `1025` |
| SSL/TLS | OFF |
| Disable STARTTLS | ON |
| User / Password | _(laisser vide)_ |

**PostgreSQL**

| Paramètre | Valeur |
|---|---|
| Host | `postgres` |
| Port | `5432` |
| Database | `weinvest_db` |
| User | `root` |
| Password | `root` |

---

## Test du webhook

### Lead prioritaire — vendeur

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

### Lead standard — acheteur

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

### Données manquantes (test de validation)

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

- **Emails reçus** : http://localhost:8025
- **Réponse webhook** : JSON contenant `leadId`, `priority` et `status`
- **Base de données** : voir les requêtes utiles ci-dessus

---

## Architecture du workflow

```
Webhook POST /webhook/lead-intake
    │
    ▼
Validate Required Fields
(firstName, email, projectType, city)
    │
    ├── false → Handle Missing Fields → Respond Error (JSON + champs manquants)
    │
    └── true  → Enrich Lead Data (leadId, receivedAt, priority, summary)
                    │
                    ▼
              Save Lead to PostgreSQL (INSERT)
                    │
                    ▼
              Check Priority (priority === "high")
                    │
                    ├── true  → Send Priority Email (HTML)
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

---

## Logique métier

**Priorité**
- `projectType === "seller"` OU `budget > 400 000` → priorité **high**
- Sinon → priorité **normal**

**Validation**
- Champs obligatoires : `firstName`, `email`, `projectType`, `city`
- Si un champ est absent, le workflow retourne une erreur JSON listant dynamiquement les champs manquants

**Email**
- Format HTML avec mise en forme professionnelle
- Contenu et couleur adaptés selon la priorité

---

## Structure du projet

```
we-invest/
├── compose.yml                    # Orchestration Docker (n8n + PostgreSQL + Mailpit)
├── docker/
│   └── postgres/
│       └── init.sql               # Création automatique de la table leads
├── workflow.json                  # Workflow n8n exporté
├── .env.example                   # Template des variables d'environnement
├── .gitignore
└── README.md
```
