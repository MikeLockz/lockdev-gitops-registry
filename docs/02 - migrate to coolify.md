# Proposal: Migrate from Komodo to Coolify

## 1. Objective
Replace the current Komodo setup with Coolify for application deployment and management. Evaluate whether Harbor is still required as a standalone container registry.

## 2. Why Coolify?
Coolify offers a more robust and feature-rich Platform as a Service (PaaS) experience compared to Komodo. Key benefits include:
- **All-in-one solution**: Manages applications, databases, and services.
- **Preview Environments**: Automatic preview deployments for Pull Requests (great for GitOps workflows).
- **Built-in Database Management**: One-click provisioning for PostgreSQL, Redis, MySQL, etc.
- **Better UI/UX**: More modern and intuitive interface.
- **Active Development**: Frequent updates and a large community.

## 3. The Harbor Question
We currently use Harbor as our container registry. Coolify does include a built-in container registry, but there are trade-offs to consider.

### Coolify Built-in Registry
- **Pros**: Integrated, simple to use, one less service to manage.
- **Cons**: Basic functionality. Lacks advanced features like vulnerability scanning, image signing, and granular RBAC.

### Harbor (Current)
- **Pros**: Enterprise-grade features (Vulnerability Scanning with Trivy, Image Signing, Replication, Advanced RBAC).
- **Cons**: Separate service to maintain and update.

### Recommendation
**Keep Harbor (for now).**
While Coolify can store images, Harbor's vulnerability scanning and security features are valuable for a "GitOps Registry" workflow. We should treat Harbor as the secure "Source of Truth" for artifacts.
- **Workflow**: CI/CD builds image -> Pushes to Harbor (Scan/Sign) -> Coolify pulls from Harbor to deploy.

*Future Consideration*: If we decide the overhead of Harbor is too high and we don't strictly need scanning/signing, we can migrate to Coolify's registry later.

## 4. Migration Plan

### Phase 1: Setup & Validation
1.  **Deploy Coolify**: Install Coolify on the management server (or a new dedicated node).
2.  **Connect Servers**: Add the existing worker nodes to Coolify.
3.  **Connect Harbor**: Configure Coolify to authenticate with the existing Harbor registry to ensure it can pull private images.

### Phase 2: Pilot Migration
1.  **Select a Pilot Service**: Choose a low-impact service currently running on Komodo.
2.  **Deploy in Coolify**: Configure the service in Coolify (connect repo, set env vars).
3.  **Cutover**: Update DNS/Ingress to point to the Coolify-managed instance.
4.  **Verify**: Ensure logs, metrics, and functionality are working as expected.

### Phase 3: Full Migration
1.  **Migrate Remaining Services**: Systematically move services from Komodo to Coolify.
2.  **Migrate Databases**: If managing DBs in Komodo, migrate data to Coolify-managed DBs or externalize them.
3.  **Update CI/CD**: Update GitHub Actions/GitOps workflows to trigger Coolify deployments (via webhooks or API).

### Phase 4: Cleanup
1.  **Decommission Komodo**: Stop and remove Komodo containers/agents.
2.  **Archive Configs**: Backup Komodo configurations for reference.
