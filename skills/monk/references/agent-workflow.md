# Agent Workflow

Use this sequence for the MVP:

1. Initialize session with workspace root.
2. Check `monk.auth.status`.
3. Check `monk.runtime.status`.
4. If signed out, call `monk.auth.start` and send the returned local URL.
5. If runtime is missing, call `monk.install.status` and surface install steps.
6. Analyze the project.
7. For new infrastructure, package-backed services, or MANIFEST/template
   changes, query available Monk packages and dump candidate packages before
   choosing providers or writing configuration.
8. Derive required user-provided secrets from the package plan and MANIFEST.
   MANIFEST `SECRET` lists values the user must supply. Do not list generated
   secrets written by packages/entities; consumers should read generated secret
   references through connections/entity state and allow them with
   `permitted-secrets` or the package-specific equivalent.
9. Request deploy-time provider and MANIFEST credentials through
   `monk.credentials.request`; use `monk.secret.request` only for a single ad
   hoc secret with no provider mapping.
10. Deploy with `monk.project.deploy`; privileged tools open their own approval
   flow when needed.
11. Verify the app or workload externally.

Never receive secret values in chat. Never bypass Monk runtime state with shell
commands.
