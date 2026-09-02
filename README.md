# Solsem Consulting workflows

Felles GitHub Actions-kontrakter for CVSmia og Karemo.

## Release-kjede

1. Produktrepoets `.github/workflows/publish.yml` eier manuell/tag-trigger, konkrete paths og token-permissions.
2. `sc-core.yml` validerer repository/solution-kontrakten.
3. `SC-Build.yml` restorer og bygger løsningen med felles .NET-oppsett.
4. `SC-Quality.yml` kjører produktets konfigurerte testprosjekter gjennom én felles testmotor.
5. `SC-Approval.yml` oppretter godkjenningssak før produksjonspublisering.
6. `sc-deploy.yml` ruter etter `github.repository` til produktets egen reusable release-workflow.
7. Produktworkflowen eier produktspesifikk pakking, signering, FTP-publisering og nettside-handoff.
8. `sc-post.yml` skriver felles sluttrapport og oppretter GitHub Release for tag-kjøringer.

Støttede ruter:

- `Solsem-Consulting/cvsmia` -> `.github/workflows/release-publish-ftp.yml@main`
- `Solsem-Consulting/KaremoSuite` -> `.github/workflows/publish-ftp.yml@main`

Begge private produktrepo må ha Actions access satt til organisasjonen slik at nested reusable workflows kan lastes. Secrets må sendes med `secrets: inherit` i hvert hopp. `GITHUB_TOKEN`-permissions kan bare beholdes eller reduseres gjennom kjeden, derfor deklareres nødvendige write-permissions i produktets inngangsworkflow.
