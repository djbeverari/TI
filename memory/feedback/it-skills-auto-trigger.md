---
name: it-skills-auto-trigger
description: Automatically suggest and use IT support skills when Daniella asks about TI work
metadata:
  type: feedback
---

# Auto-Trigger IT Skills

**Rule:** When Daniella mentions anything IT-related (troubleshooting, support, tickets, projects, documentation, analysis), automatically suggest and offer to use the appropriate skill from CLAUDE.md "IT Support & Management Skills" section.

**Why:** IT work follows patterns. Each task type has a best-fit skill that structures the work better.

**How to apply:**

1. **Detect IT context** — keywords: "suporte", "ticket", "problema", "infraestrutura", "servidor", "usuário", "antivírus", "documentar", "organizar", "priorizar", "projeto", "sprint", "métrica"

2. **Automatically suggest skill:**
   - Troubleshooting → offer `customer-support:kb-article` + `customer-support:draft-response`
   - Organizing work → offer `customer-support:ticket-triage` + `productivity:task-management`
   - Planning → offer `product-management:sprint-planning`
   - Analyzing data → offer `data:analyze` + `enterprise-search:search`

3. **Be proactive** — Don't wait for user to ask; offer the skill at the start of the turn

Example:
```
User: "Temos vários tickets de suporte sobre o Kaspersky"
Claude: "Vou ajudar. Quer que eu use `customer-support:ticket-triage` 
para organizar por prioridade, ou `customer-support:kb-article` 
para documentar as soluções?"
```

**Strategic Level Keywords:** roadmap, strategy, planning, budget, ROI, trends, vendor, competitive, leadership, stakeholder, KPI, initiative, vision

**Strategic Suggestions:**
- Planning infrastructure → offer `product-management:roadmap-update`
- Comparing tools/vendors → offer `product-management:competitive-brief`
- Analyzing performance data → offer `product-management:metrics-review`
- Brainstorming initiatives → offer `product-management:brainstorm`
- Presenting to leadership → offer `product-management:stakeholder-update`
- Researching best practices → offer `product-management:synthesize-research`

Example (Strategic):
```
User: "Preciso apresentar um roadmap de segurança para a diretoria"
Claude: "Vou ajudar. Recomendo usar `product-management:roadmap-update` 
para estruturar o plano, depois `product-management:stakeholder-update` 
para preparar a apresentação."
```

**Don't force** — if the user's intent is unclear or they explicitly decline, respect that.
