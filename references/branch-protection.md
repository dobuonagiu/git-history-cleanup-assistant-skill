# Fase 4: analisi delle protezioni per provider

Verificare: protected branches, push restrictions, required approvals, PR mandatory checks (e blocco force push).
Se presenti: fermarsi e chiedere all'utente di rimuoverle temporaneamente; non procedere senza conferma.
Annotare lo stato originale per poterle riattivare (Fase 16).

## GitHub
```bash
gh api repos/<owner>/<repo>/branches --paginate --jq '.[] | select(.protected) | .name'
gh api repos/<owner>/<repo>/branches/<branch>/protection
gh api repos/<owner>/<repo>/rulesets
```
Settings → Branches / Rules. Verificare "Allow force pushes", "Restrict who can push", required reviews,
status checks, rulesets. Org-level rulesets richiedono admin dell'org.

## GitLab
```bash
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://<host>/api/v4/projects/<id>/protected_branches"
```
Settings → Repository → Protected branches ("Allowed to force push"), Merge request approvals, Push rules.

## Azure DevOps
Repos → Branches → Branch policies; Repos → Security (permesso "Force push (rewrite history and delete branches)").
```bash
az repos policy list --repository-id <id> --branch <branch>
```

## Bitbucket
Repository settings → Branch restrictions (prevent rewriting history, prevent deletion, merge checks, required approvals).

## Note
- Alcuni provider hanno un default branch protetto non rimovibile: serve un cambio temporaneo del default branch.
- Se non si hanno i permessi per leggere/modificare le protezioni → interrompere il processo (Fase 2).
