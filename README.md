# Solsem Consulting workflows

Felles GitHub Actions-kontrakter for CVSmia og Karemo.

## Release-kjede

1. Produktrepoets `.github/workflows/publish.yml` eier manuell/tag-trigger, konkrete paths og token-permissions.
2. `sc-core.yml` validerer repository/solution-kontrakten.
3. `SC-Build.yml` restorer og bygger løsningen med felles .NET-oppsett.
4. `SC-Quality.yml` kjører produktets konfigurerte testprosjekter gjennom én felles testmotor.
5. `SC-Approval.yml` oppretter godkjenningssak før produksjonspublisering.
6. Produktets `publish.yml` kaller produktets lokale reusable deployment-workflow direkte.
7. Den lokale deployment-workflowen eier produktspesifikk pakking, signering, FTP-publisering og nettside-handoff.
8. `sc-post.yml` skriver felles sluttrapport og oppretter GitHub Release for tag-kjøringer.

Produktspesifikke deploy-kontrakter:

- `Solsem-Consulting/cvsmia`: `publish.yml` -> `./.github/workflows/release-publish-ftp.yml`
- `Solsem-Consulting/KaremoSuite`: `publish.yml` -> `./.github/workflows/publish-ftp.yml`

Det finnes med hensikt ingen felles deployment-router. Dermed trenger ikke Karemo å laste eller validere CVSmias deployment-workflow, og CVSmia trenger ikke å laste eller validere Karemo sin. Produktets deployment-workflow skal bare eksponere `workflow_call`; alle eksterne release-triggere eies av produktets `publish.yml`.

Begge private produktrepo må ha Actions access satt til organisasjonen slik at de felles build-, quality-, approval- og post-workflowene kan lastes. Secrets må sendes eksplisitt eller med `secrets: inherit` i hvert hopp. `GITHUB_TOKEN`-permissions kan bare beholdes eller reduseres gjennom kjeden, derfor deklareres nødvendige write-permissions i produktets inngangsworkflow.
