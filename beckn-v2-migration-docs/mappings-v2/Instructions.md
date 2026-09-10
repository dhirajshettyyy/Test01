# Instructions

## Step 1: Get the Latest Code

**If this is a fresh setup**, clone the repository:

```bash
git clone https://github.com/abhey-WIL/beckn-v2-migration-docs
```

**If you already have the repository**, pull the latest changes:

```bash
git pull
```

---

## Step 2: Update the Mapper File

No changes are required to the configuration files.

Simply copy the updated mapper from:

```
V2/mappings/mappings.yaml
```

and paste it into your existing mapper file, replacing its contents.

---

## Step 3: Start the Container

Start the services using your specific Docker Compose file:

```bash
docker compose -f docker-compose-adapter.yml up -d
```

---

## Step 4: Import the Postman Collection

To test the flow, import the V2 Postman collection into Postman:

```
V2/Postman/UP ONA.postman_collection.json
```

In Postman: **File → Import** → select the file above.
