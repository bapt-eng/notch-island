---
name: notch-island
description: Dynamic Island 3.0 sous l'encoche du MacBook avec modèle Liquid Glass 3D (dégradé noir vers verre translucide avec biseau spéculaire Apple), intégration native Apple Music (Now Playing & scrubber), calibrage millimétrique notch (179x32mm), HUD de chargeur intelligent (Watts & MagSafe) et salle d'attente de fichiers.
---

# 🏝️ Dynamic Island 3.0 — Liquid Glass 3D, Apple Music & Calibrage Notch (MacBook)

Notch Island (`agy-island`) est une Dynamic Island native Apple écrite en Swift/SwiftUI pour macOS, calibrée au millimètre près sur l'encoche physique (*Notch*) de l'écran.

Elle fonctionne de manière **100% autonome 24h/24 en arrière-plan** (LaunchAgent macOS natif, 0% CPU au repos, mémoire bridée pour Mac 8GB RAM).

---

## ✨ Nouveautés & Raffinements (Version 3.0)

### 1. 🪟 Modèle Obligatoire Liquid Glass 3D (Inspiré des Widgets Apple VisionOS)
- **Dégradé Vertical Organique :**
  - **Sommet (100% Noir Profond) :** Épouse et fait disparaître complètement l'encoche physique sans aucune démarcation visuelle.
  - **Base (Verre Translucide Réfractif) :** Laisse subtilement transparaître le fond d'écran et les fenêtres en arrière-plan grâce au moteur `NSVisualEffectView` en mode `.behindWindow`.
- **Relief 3D Spéculaire & Caustiques :**
  - Halo volumétrique diffusé en sous-couche (teinte magenta Apple Music ou cyan).
  - Lèvre inférieure lumineuse et biseau optique ultra-net (`LinearGradient` blanc pur 98% sur l'arc inférieur) pour donner un détachement tridimensionnel luxueux.
  - Double ombre portée 3D (ombre de contact courte + ombre atmosphérique étendue).

### 2. 🎯 Calibrage Millimétrique Notch (Zéro Débordement)
- **Dimensions Exactes Mesurées sur le Matériel :**
  - Largeur physique de l'encoche : **179 px** (détection matérielle via `auxiliaryTopLeftArea` et `auxiliaryTopRightArea`).
  - Hauteur de l'encoche : **32 px** (alignée sur la barre de menus).
- **Mode Compact :** S'insère **strictement dans l'encoche** (180 px × 32 px, rayon de 10 px) sans dépasser d'un seul pixel sur l'espace de travail.
- **Mode Déployé Élégant :** Réduit à 324 px × 128 px (au lieu des 420-540 px excessifs précédents), évitant toute obstruction excessive de l'écran.

### 3. 🎵 Onglet Exclusif Apple Music (Now Playing & Contrôles)
- **Synchronisation Système Directe :** Écoute officielle `com.apple.Music.playerInfo` via `NSDistributedNotificationCenter` et passerelle AppleScript rapide (< 50ms).
- **Interface Lecteur Dédiée :**
  - Badge Apple Music carré arrondi magenta (`#FA233C` vers `#AF28E6`).
  - Titre, artiste et album en typographie arrondie San Francisco.
  - Barre de défilement temporelle (*scrubber*) avec temps écoulé et durée totale.
  - Boutons de transport : Précédent, Lecture/Pause avec bouton circulaire magenta lumineux, et Suivant.
  - **Égaliseur Audio Animé :** Barres de fréquence vivantes réactives à la lecture en temps réel.
- **Mini-Ticker Compact :** Quand un morceau joue, l'îlot compact affiche une note magenta Apple Music et un mini égaliseur animé sans déborder de la barre de menus.

### 4. ⚡ HUD de Chargeur & Puissance en Watts
- **Détection Matérielle Instantanée (IOKit) :** Dès qu'un câble de charge (MagSafe 3 ou USB-C Power Delivery) est branché, l'île s'étire.
- **Affichage des Watts :** Puissance exacte (`30W`, `67W`, `96W`, `140W`) et badge `RAPIDE`.
- **Jauge Circulaire de Batterie :** Anneau de progression vert émeraude avec pourcentage exact.

### 5. 📁 Salle d'Attente de Fichiers & Captures d'Écran (*Screenshot & Drop Shelf*)
- **Glisser-Déposer Universel :** Fichiers, dossiers, mais aussi **captures d'écran et images brutes** (PNG, JPEG, TIFF, UTType image, CleanShot, vignettes de capture macOS, glisser depuis navigateurs).
- **Vignettes Visuelles Réelles :** Les images et captures affichent un aperçu visuel miniature avec biseau cyan et icône caméra dédiée.
- **Bouton 📸 Capture Rapide :** Déclenche instantanément la capture d'écran interactive macOS (`screencapture -i`) directement depuis la Dynamic Island.
- **Bouton 📋 Coller :** Colle immédiatement une image ou un fichier présent dans le presse-papier.
- **Double-clic & Redéploiement :** Double-clic pour ouvrir en grand dans Aperçu, et glisser vers l'extérieur (`.onDrag`) pour partager vers Discord, Slack, Safari, Mail ou le Finder.

### 6. 🧠 Révision Flashcards Périodique (Toutes les 30 min) & Assombrissement d'Écran Focus
- **Déclenchement Automatique Intelligent :** Toutes les 30 minutes de travail actif (veille/sommeil de l'écran pris en compte), l'île jaillit vers le bas avec une animation fluide spring Apple.
- **Assombrissement Cinématique de l'Écran (*Focus Dimmer*) :** Un panneau sombre translucide (68% noir OLED) recouvre l'intégralité du bureau pour éliminer toute distraction visuelle. L'écran reste assombri tant que la carte n'est pas retournée ni validée !
- **Révélation Interactive & Formules :**
  - **Espace** ou clic : Dévoile la solution mathématique détaillée (équations avec typographie monospacée haute fidélité, astuces de cours).
  - **Entrée** ou clic "✅ Maîtrisé" : Valide la maîtrise, incrémente le niveau et rétablit instantanément la clarté normale de l'écran.
  - **Échap** ou clic "🔁 À revoir" : Conserve la carte pour le prochain cycle de 30 min et replie l'île.

### 7. 🎨 Application Studio Dédiée Apple (*NotchFormulas.app*)
- Interface SwiftUI macOS avec navigation split view, gestion par catégories (Mécanique, Électromagnétisme, Thermodynamique, Mathématiques, Ondes).
- Ajout, modification, recherche en temps réel, réglage de cadence (15 min, 30 min, 45 min, 1h), et bouton de test immédiat à l'encoche.

### 8. 🛡️ Sauvegarde et Réversibilité Intégrale
- L'ancienne version v2 est archivée dans `backup_v2/` et restaurable en un clic via `agy-island restore`.

---

## 🕹️ Commandes Terminal (`agy-island` & `agy-formulas`)

```bash
# Ouvrir le Studio de Formules Apple
agy-formulas

# Déclencher immédiatement une révision flashcard à l'encoche (avec assombrissement)
agy-island flashcard

# Déclencher une formule spécifique par identifiant
agy-island flashcard tmc-barycentrique

# Fermer la révision et restaurer la luminosité de l'écran
agy-island flashcard-dismiss

# Régler la cadence de révision (ex: 15, 30 ou 60 minutes)
agy-island interval 30

# Vérifier le statut, le PID et l'empreinte mémoire
agy-island status

# Déclencher une capture d'écran interactive à l'encoche
agy-island screenshot

# Coller une capture/image du presse-papier dans l'île
agy-island paste

# Contrôler Apple Music
agy-island music play
agy-island music pause
agy-island music next
agy-island music prev

# Basculer l'onglet actif à l'encoche
agy-island tab music
agy-island tab shelf

# Tester l'animation de charge avec puissance personnalisée (ex: 96W, 140W)
agy-island test-charge 140

# Redémarrer l'application
agy-island restart

# Restaurer l'ancienne version en cas de besoin
agy-island restore
```

