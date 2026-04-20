# Brand Instance Setup Checklist

Use this checklist to spin up a new branded instance (e.g. MCL, ALLDOQ).

## 1. Create the tenant (super admin)
1. Log in to the platform admin at `https://admin.<your-domain>/super`
2. Go to Tenants → New tenant
3. Set slug (e.g. `mcl` or `alldoq`), name, and allow_local_login
4. Save — provisioning runs automatically (creates schema + seeds default groups/ACLs)

## 2. Configure branding (super admin)
1. Go to Tenants → [tenant] → Edit
2. Set theme colours: primary, secondary, accent
3. Toggle enabled sections — select which of the 14 sections this brand will show

## 3. Create the first admin user (tenant admin)
1. Go to the tenant's login URL: `https://<slug>.<your-domain>/login`
2. Use the super admin console (or direct DB insert) to invite the first user and set `is_admin = true`
3. User accepts invitation, sets password

## 4. Configure groups & permissions (tenant admin)
1. Log in as the admin user
2. Go to Admin → Users → invite all staff
3. Assign users to groups: people_and_culture, it, finance, communications, compliance_officers
4. Section ACLs are pre-seeded from SectionRegistry defaults — adjust per brand requirements via Admin → Users → [user] → Permissions

## 5. Create subsections (tenant admin)
For sections that support subsections (HR, Departments, Docs, Projects):
1. Go to Admin → Sections → [section] → Subsections
2. Create subsections (e.g. HR → Payroll, Benefits, Onboarding)
3. Grant subsection-level ACLs to relevant groups

## 6. Enable SSO (optional, super admin)
1. Go to Tenants → [tenant] → IDPs
2. Add OIDC or SAML provider configuration
3. Test login flow

## 7. Seed content
1. Log in as a Communications team member
2. Post first announcement on the Home page
3. Draft and publish first News article
4. Add Tools & Applications links
5. Upload any existing policies to Compliance section
