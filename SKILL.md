---
name: notch-island
description: Visual AI Command Center & Dynamic Island for the MacBook Notch (Claude Code MCP & Agentic IPC).
---

# 🏝️ NotchIsland 3.0 : Visual AI Command Center for MacBook Notch

Dynamic Island 3.0 native sous l'encoche du MacBook avec modèle **Liquid Glass 3D** (biseau spéculaire Apple, translucidité progressive, calibrage millimétrique notch $179 \times 32\,\text{mm}$), **serveur MCP Claude Code / AGY**, **HUD de chargeur intelligent (Watts & MagSafe)** et **salle d'attente de fichiers**.

---

## 🏛️ Architecture & Fonctionnalités

1. **Intégration Claude Code & Agents IA (MCP & IPC) :**
   - Notification visuelle animée sous l'encoche dès qu'un agent termine une tâche, échoue un test ou attend une saisie utilisateur.
   - Serveur MCP Python unifié (`notch_island_server.py`) exposant `notch_island_notify` et `notch_island_status`.
   - Script CLI direct : `claude_code_hook.sh "<message>" "<titre>"`.

2. **Liquid Glass 3D Natif AppKit :**
   - Shader d'effet verre VisionOS avec réfraction spéculaire et flou dynamique.
   - Zéro webview, 0.0% CPU au repos, empreinte mémoire stricte sous 15 MB.

3. **HUD MagSafe & Télémétrie Matérielle :**
   - Mesure directe via IOKit des Watts de charge réels en temps réel.

4. **Staging Shelf (File Drop Zone) :**
   - Zone de rétention temporaire sous l'encoche permettant de glisser-déposer des fichiers ou captures avant envoi à l'agent.

---

## 🕹️ Commandes Terminal (`agy-island`)

```bash
# Envoyer une notification directe sous l'encoche
agy-island message "Tests unitaires passants (42/42) en 1.2s" "Claude Code"

# Mode build en cours
agy-island message "Compilation du noyau en cours..." "Compilateur"

# Fermer la notification
agy-island dismiss
```
