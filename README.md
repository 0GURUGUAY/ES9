# ES-9 Mixer

Console native macOS 13+ pour les 14 entrées analogiques de l'Expert Sleepers ES-9.
SwiftUI et CoreMIDI, sans dépendance externe ni moteur audio sur le Mac.

## Lancer

L'application compilée se trouve dans `dist/ES-9 Mixer.app`. Double-cliquer dessus.
Pour reconstruire avec les outils de développement Apple :

```sh
bash scripts/build-app.sh
```

La compilation vise l'architecture du Mac utilisé. La signature est locale (ad hoc),
pas une signature Developer ID ni une notarisation pour distribution publique.
L'icône macOS représente un fader sur fond sombre, avec un repère cyan.
Le curseur métallique élargi et ses rainures restent visibles aux petites tailles.
Elle est générée dans toutes les résolutions nécessaires par
`scripts/generate-icon.swift` et intégrée automatiquement lors de la compilation.

## Premier essai

Les commandes de l’ancien bandeau supérieur se trouvent dans la barre de menus
macOS, libérant la hauteur de la fenêtre pour les tranches :

- **Session** : ouvrir (`⌘O`), enregistrer sous (`⇧⌘S`), restaurer une sauvegarde ES-9.
- **ES-9** : mode courant, **MUTE ALL**, **Configurer MIDI** (`⌘,`),
  activer ou suspendre, vérifier et mémoriser avec confirmation.
- **Launch Control** : sélectionner la banque, avec une coche sur la banque active.
- **Affichage** : sélectionner **Console**, **Matrice** ou **Strip**, avec une coche sur la vue active.
  La colonne à gauche de la fenêtre propose les mêmes trois vues en un clic,
  sous un bouton **CONNECTER** qui active l'ES-9 (ou ouvre la configuration MIDI
  si ses ports ne sont pas choisis) ; une fois connecté il affiche **DIRECT** et
  un clic suspend le contrôle.

Le menu **MUTE ALL** est coché pendant la coupure et un avertissement rouge
reste visible dans la fenêtre. Le mode Direct/Démo et la charge DSP restent
affichés dans la barre d’état. Les commandes sont indisponibles pendant une
opération MIDI ou lorsque la configuration MIDI ou la confirmation de
mémorisation est ouverte.

1. La console démarre en démonstration, même si l'ES-9 est connecté.
2. Brancher l'ES-9 et le Launch Control XL MK2 par USB au Mac.
3. Dans **Configurer MIDI**, vérifier les ports et interroger la version de l'ES-9.
4. Choisir un template **User** du Novation et apprendre les 8 faders, les 8 mutes,
   les 8 solos, éventuellement les 8 panoramiques et les deux boutons de banque.
5. Réduire le volume des enceintes. **Activer sur l'ES-9** applique directement
   la configuration du mélangeur, sans confirmation ni sauvegarde automatique.
   Exporter au préalable un dump `.syx` avec l'outil officiel si vous souhaitez
   pouvoir restaurer la configuration actuelle.
6. Vérifier avec une seule source audio, puis ajouter les autres progressivement.

Les faders d'entrée sont limités à 0 dB, démarrent à -18 dB et le général à -12 dB.
Les huit faders de sortie jack démarrent à 0 dB pour conserver les niveaux des
sessions précédentes ; ils atténuent ensuite le mélange affecté à chaque sortie.
Les sources sont additionnées : ces précautions ne garantissent pas l'absence de
saturation. Il n'y a pas de vumètre simulé ou de limiteur.

### Casque

Les contrôles ci-dessous concernent le mix analogique. Le retour USB 3–4
arrive au casque indépendamment de ces contrôles et du bouton **Écoute**.

La tranche **CASQUE** diffuse les entrées affectées au **Général**, avec leurs
niveaux, panoramiques et mutes, mais **avant le fader général**. Son volume est
indépendant des sorties principales ; les entrées affectées exclusivement aux
sorties jack ne sont pas envoyées au casque.

L'**Écoute** est désactivée par défaut, y compris à l'import d'une ancienne
session. Baisser le volume physique du casque avant de l'activer. Le fader casque
démarre à -18 dB et peut atteindre +12 dB, comme le mélangeur officiel. Ce gain
peut saturer lors de l'addition de sources ; ce n'est pas un limiteur. Le
potentiomètre physique de l'ES-9 reste le contrôle final du volume casque.

Pour tester le synthétiseur sur l'entrée 1, activer son envoi au **Général**
dans la colonne correspondante de la vue **Matrice**, activer **Écoute**, puis
activer la console.
Monter les niveaux progressivement. Le routage casque est désormais inclus
dans l'activation, les mises à jour, la vérification et la session enregistrée :
il n'est plus un ajout temporaire supprimé par une réactivation.

### Vérifier le trajet entrée 1 vers sortie jack 1

1. Brancher la source sur l'entrée 1, choisir la vue **Matrice**, décocher
   **Routage verrouillé**, activer la case entrée 1 / sortie 1 à **0 dB** et
   décocher **Général** pour cette entrée. Vérifier que les mutes sont désactivés.
2. Activer la console. En démonstration ou après suspension, les mouvements des
   faders ne sont pas envoyés au module.
3. Baisser fortement le volume d'écoute avant de monter le fader de l'entrée 1
   à **0 dB** pour ce test. Le général n'agit pas sur cette sortie jack.
4. Jouer sur la source et observer la sortie 1. Une LED éteinte ne suffit pas
   à conclure à un mauvais routage : à -40 dB, le signal est environ 100 fois
   plus faible qu'à 0 dB.
5. Revenir au niveau d'écoute souhaité après le test.

Le trajet entrée 1 vers sortie jack 1 à 0 dB a été vérifié sur un ES-9 avec
firmware 1.3.1, par relecture de configuration et observation de la LED de
sortie avec un synthétiseur. La LED d'entrée restait éteinte pendant cet essai ;
elle n'est donc pas utilisée comme condition préalable à ce diagnostic.
Les autres trajets ne sont pas validés par ce seul essai. Une relecture confirme
les réglages, pas la présence du son. Si l'outil officiel a été utilisé entre
temps, suspendre puis réactiver la console pour remettre son routage en place.

## Vue Strip

La vue **Strip** présente quatre entrées comme des tranches de console analogique
(entrées **10 à 13** par défaut). La liste déroulante en haut de chaque tranche
choisit l'entrée affichée et indique le nom de chaque voix. Chaque tranche
contient, de haut en bas :

1. **GAIN** : trim numérique de −24 à +12 dB appliqué à tous les envois de
   l'entrée. L'ES-9 n'a pas de préampli réglable : au-delà de 0 dB, surveiller
   la saturation numérique.
2. **ÉGALISEUR** 3 bandes (LOW, MID, HIGH) : fréquence, Q et niveau (±15 dB).
   LOW et HIGH peuvent passer en **SHELF** (Q inactif, HIGH limité à +12 dB).
   Il utilise les filtres natifs de l'ES-9 et reste désactivé tant que
   **EQ IN** n'est pas enclenché. L'EQ est placé avant les mélangeurs : il
   s'applique à toutes les destinations de l'entrée, casque compris, et
   consomme du DSP.
3. **ROUTAGE · SORTIES 1–4** : niveau d'envoi vers chaque sortie et bouton
   ON/OFF (le bouton exige un routage déverrouillé).
4. **VOLUME** : fader de l'entrée.
5. **MUTE** et **SOLO**.

Les potards se règlent en glissant vers le haut ou la droite, **⌥** pour le
réglage fin, double-clic pour revenir à la valeur par défaut. Les sorties 1–4,
le général et le casque sont affichés à droite avec des potars de niveau
(à la place des faders), leurs boutons MUTE/SOLO et l'interrupteur **Écoute**.

## Matrice de routage

Le sélecteur **Console / Matrice / Strip** change uniquement l'affichage : les vues
pilotent la même session. La matrice présente les 14 entrées en lignes et les
8 sorties jack en colonnes. Une entrée peut alimenter plusieurs sorties et
chaque sortie peut recevoir plusieurs entrées.

1. Décocher **Routage verrouillé**.
2. Cocher une case pour activer sa liaison. Le niveau initial d'une liaison est
   **0 dB** ; son curseur permet de l'atténuer jusqu'à **−∞**.
3. Régler les faders d'entrée et de sortie dans la console. Le gain final est
   le produit des gains **entrée × liaison × sortie** ; les mutes et solos
   restent actifs sur toutes les liaisons concernées.
4. Recocher **Routage verrouillé**. Les niveaux des liaisons restent réglables,
   mais leur activation et les envois au général sont verrouillés.

La colonne **Général** active indépendamment l'envoi stéréo de chaque entrée,
avec son panoramique. Le casque suit toujours cet envoi avant le master, et
non les liaisons jack. La console affiche le nombre d'envois jack par entrée.
Le routage au général se règle dans cette matrice ; la console garde les bandes
plus épurées pour privilégier les faders. Décocher une liaison conserve son
niveau pour sa prochaine activation.

Pour utiliser librement les **112 liaisons simultanées**, cliquer sur
**Jacks uniquement** et confirmer : cela coupe tous les envois au général
(donc aussi son écoute casque), sans effacer les liaisons jack ni leurs niveaux.
Les retours USB directs restent actifs sur toutes leurs destinations.
Réduire le volume avant les essais : l'addition de sources peut saturer.

Chaque mélangeur interne possède huit destinations mono. Le général en utilise
deux et son casque deux supplémentaires. L'application cherche une répartition
des 14 entrées entre les deux mélangeurs, avec chaque entrée dans un seul
mélangeur. Si aucune répartition ne convient, la modification est refusée avec
une erreur explicite : la session précédente et le routage matériel sont conservés.
Cette version ne cascade pas les mélangeurs et ne duplique pas leurs entrées
pour contourner cette limite. Mutes et niveaux à −∞ ne libèrent pas de destination ;
décocher les liaisons pour libérer les ressources.

Les anciennes sessions à destination exclusive sont converties automatiquement :
le même général ou jack reste actif, avec un gain de liaison de 0 dB et sans
changement des faders. Les nouvelles sessions enregistrent toutes les liaisons
et leurs niveaux ; elles ne sont pas compatibles avec l'ancienne application.

## Fonctionnement

Les faders, mutes, solos et envois décrits ici contrôlent uniquement le mix
analogique, jamais les retours USB directs.

- Chaque entrée a un nom, fader, mute, solo, des envois et un panoramique.
- Chacune des huit sorties jack a un nom, fader, mute et solo. Son niveau
  multiplie celui de toutes les entrées qui lui sont affectées, sur les deux
  mélangeurs internes. Une sortie sans entrée affectée ne reçoit aucun mix
  analogique, mais peut toujours recevoir son canal USB direct.
- Les solos sont cumulatifs : plusieurs solos permettent d'écouter plusieurs
  tranches ensemble. Le mute reste prioritaire, même sur une tranche en solo.
- Un solo d'entrée coupe les autres entrées sur toutes leurs destinations,
  casque compris. Un solo de sortie coupe uniquement les autres sorties jack :
  le général et le casque restent indépendants. Les deux groupes de solos
  peuvent être utilisés simultanément.
- Le bouton **MUTE ALL**, commun aux vues Console et Matrice, coupe les
  14 entrées analogiques sur le général, le casque et les jacks. Il est
  coché dans le menu **ES-9** lorsqu’il est actif, avec un avertissement rouge
  dans la fenêtre. Un second clic rétablit l’écoute selon les
  mutes et solos individuels, sans les avoir modifiés. Les retours USB directs
  ne sont pas coupés : ce n’est pas un arrêt d’urgence de toutes les sorties.
  Les LED Mute des entrées du Launch Control deviennent rouges pendant la
  coupure, puis retrouvent leur état individuel. Les réglages individuels
  restent modifiables pendant la coupure et s’appliquent à sa levée.
  L’état **MUTE ALL** est enregistré dans la session ; les anciennes sessions
  le chargent désactivé. En démonstration ou après **Suspendre**, comme les
  autres contrôles, il n’agit sur le matériel qu’à l’activation de la console.
- Envois multiples : général stéréo et/ou sorties jack 1 à 8.
- Le **Routage verrouillé** est activé par défaut, y compris à l'import d'une
  ancienne session. Décocher uniquement pour changer les destinations, puis
  recocher. Le verrouillage est sauvegardé avec la session. Les faders, mutes
  et solos, ainsi que les niveaux de liaison, n'envoient que des changements de coefficients, sans réaffectation
  d'entrées ou de sorties matérielles.
- Panoramique à puissance constante sur le général, ignoré sur les sorties mono.
- Le fader général ne modifie pas les sorties jack.
- Le bouton **MUTE** de la tranche **GÉNÉRAL** coupe uniquement son mix
  analogique stéréo, sans modifier le fader, les mutes individuels, le casque
  avant master ni les sorties jack. Un second clic rétablit ce mix au niveau
  du fader. Le bouton et le pictogramme deviennent rouges pendant la coupure.
  Les retours USB directs restent audibles. Ce mute est indépendant de
  **MUTE ALL** et sauvegardé dans la session ; il est désactivé par défaut
  dans les anciennes sessions.
- Deux mélangeurs internes reçoivent normalement chacun 7 entrées. Leurs sorties sont allouées
  automatiquement et additionnées par l'ES-9. Si le casque demande deux sorties
  supplémentaires, les entrées sont redistribuées entre les mélangeurs lorsque
  nécessaire, avec au plus huit entrées et huit destinations mono par mélangeur. Cette répartition
  matérielle ne change ni les numéros des entrées ni les banques MIDI.
- Un changement d'affectation coupe momentanément le mélangeur concerné avant
  de modifier son routage : pas de réaffectation d'une sortie avec un ancien gain.
  Une brève interruption est donc possible. Le lissage DSP n'est pas activé.
- Le mix analogique reste dans le module ; cette application ne transporte que
  les commandes MIDI. VCV ou une DAW peuvent simultanément envoyer de l'audio
  par USB vers les sorties physiques (voir ci-dessous).
- L'activation relit et vérifie le routage et les coefficients avant d'annoncer
  que le contrôle est actif. **Vérifier** permet de refaire cette lecture.

### Ce que l'activation remplace

La console nécessite les deux mélangeurs : **S/PDIF désactivé**. Elle gère les
64 filtres d'EQ d'entrée (désactivés sauf **EQ IN** de la vue Strip) et les vérifie à la
relecture, désactive les liens stéréo macro et le contrôle CC direct de l'ES-9,
met les offsets des sorties à zéro, active les filtres anti-DC des 14 entrées
(usage audio uniquement, pas CV), et configure le passage direct USB décrit
ci-dessous. Les retours USB s'additionnent au mix analogique sur les sorties communes.

Le **lissage natif des 16 sorties des mélangeurs** est activé et vérifié à la
relecture. Il adoucit les changements de coefficients (faders, pans, mutes,
solos et niveaux de liaison), sans multiplier les messages MIDI. Suspendre
puis réactiver la console après cette mise à jour pour l'appliquer au matériel.
Les changements de routage et l'activation peuvent encore être audibles :
réduire le volume pour ces opérations. L'absence totale de clics reste à
confirmer à l'écoute sur le matériel.

Les 14 entrées sont toujours envoyées aux canaux d'enregistrement USB 1 à 14.
Les canaux d'enregistrement USB 15 et 16 ne transportent plus le S/PDIF.
La sortie casque reçoit le mix décrit ci-dessus si son écoute est activée,
en plus du retour USB direct 3–4 qui reste indépendant. Les sorties ES-5 ne sont pas
alimentées par cette console. Le fader général désigne uniquement les deux
sorties principales symétriques.

Ne pas utiliser simultanément le configurateur officiel ou un autre contrôleur
qui modifie la configuration : l'application ne surveille pas en continu les
modifications externes. Une déconnexion suspend le contrôle ; il ne se réactive
jamais automatiquement.

### VCV Rack / Audio 16 : retour USB direct

Dans le module **Audio 16** de VCV Rack, sélectionner le pilote **Core Audio**,
le périphérique **ES-9** et les 16 canaux à partir du canal 1. Brancher les
signaux de VCV sur les prises **To device** du module :

| Canal USB / Audio 16 | Sortie physique ES-9 |
| --- | --- |
| 1–2 | Sorties principales gauche / droite |
| 3–4 | Casque gauche / droite |
| 5–8 | Inutilisés (S/PDIF désactivé, ES-5 non alimenté) |
| 9–16 | Jacks 1–8, respectivement |

Cette numérotation conserve les canaux des jacks de la configuration usine.
Le casque reçoit directement les canaux 3–4, sans la somme 1–2 + 3–4 de la
configuration usine. Pour écouter le même signal sur le général et le casque,
le brancher aux deux paires dans VCV.

**Baisser les volumes dans VCV et le volume physique du casque avant activation.**
Le retour USB est direct, sans atténuation par la console : ses faders, mutes,
solos et le bouton **Écoute** agissent uniquement sur le mix analogique.
Un mute de sortie ou un général à −∞ ne coupe donc pas VCV. Régler ou couper
le signal USB dans VCV ; le potentiomètre physique reste actif pour le casque.
Les signaux USB et analogiques s'additionnent si leurs destinations sont communes,
avec un risque de saturation. Éviter également une boucle entrée ES-9 → VCV →
sortie ES-9 → même entrée.

Les prises **From device** continuent de recevoir les entrées analogiques
1 à 14. Ce retour direct ne consomme aucun emplacement des deux mélangeurs.
L'activation et **Vérifier** contrôlent le routage USB par relecture.
Après mise à jour, fermer et rouvrir l'application compilée, puis suspendre
et réactiver la console pour appliquer ce routage. Une relecture conforme
ne prouve pas la présence de son : tester chaque sortie à faible niveau.

**Suspendre** cesse les commandes mais laisse l'audio et les réglages en place.
**Restaurer une sauvegarde ES-9** recharge un dump `.syx` et vérifie son contenu.
Cela ne réécrit pas les mémoires permanentes.
La restauration transmet les 768 mots en 24 blocs SysEx de 32 mots, comme
l'outil officiel, puis relit la configuration pour confirmer son contenu.

### Launch Control XL MK2

L'apprentissage évite de supposer un mapping d'usine. Utiliser des CC absolus
pour les faders/pans et des CC ou notes momentanés pour les boutons (valeur
non nulle à l'appui, zéro au relâchement). Les templates avec boutons à bascule
ne sont pas pris en charge. Chaque message doit avoir une affectation unique.

Banque 1 : entrées 1-8 ; banque 2 : entrées 9-14, contrôles 7-8 inactifs ;
banque 3 : sorties jack 1-8, panoramiques inactifs car sorties mono.
Les boutons de banque passent à la banque précédente ou suivante sans boucler.
Apprendre également les huit boutons **Solo** si souhaité. Les affectations
**Général** et **Casque** utilisent des CC indépendants des banques, avec le
même rattrapage que les faders. Le CC casque ne bascule pas l'Écoute.
La fenêtre MIDI présente une section **Solo — 8 contrôles** : cliquer sur
**Apprendre** pour chaque bouton. Les solos suivent les trois banques et restent
cumulatifs, avec priorité au mute.

La courbe des faders MIDI (entrées, sorties, général et casque) réserve les
**0–40 %** de course à une atténuation progressive en dB, puis les **40–100 %**
à un gain linéaire, de 10 % à 100 % du gain maximal. Pour les entrées, sorties
et général : 20 % = −40 dB, 40 % = −20 dB, 50 % ≈ −12 dB,
70 % ≈ −5,2 dB, 100 % = 0 dB ; zéro coupe complètement le son.
Le casque conserve son plafond de +12 dB. La courbe est identique dans les deux
sens de mouvement. Les curseurs à l'écran et les sessions conservent leur
échelle en dB et leurs niveaux existants ; seul le geste MIDI change.
Le rattrapage compare les positions physiques avec la courbe inverse.

Le rattrapage empêche un fader ou pan de changer une valeur après changement de
banque ou modification à la souris avant d'avoir rejoint la valeur affichée.
Le retour LED Mute/Solo utilise la sortie MIDI du Launch Control sélectionnée
dans la configuration MIDI. Dans Novation Components, régler le canal LED de
chaque bouton sur le même canal que son canal MIDI d'envoi. Les LED suivent la
banque affichée ; Mute est rouge et Solo vert. Le routage depuis les
potentiomètres n'est pas disponible.
Le Mac et l'application doivent rester ouverts pour ce pilotage physique.

### Sauvegardes

La session (noms, niveaux, mutes, solos, sorties, destinations, verrouillage et mapping MIDI) est enregistrée
automatiquement dans `~/Library/Application Support/ES9Mixer/session.json`.
Le menu **Session** permet aussi d'exporter/importer un fichier JSON.
Ce n'est pas une sauvegarde complète du matériel : le fichier `.syx` préalable
conserve sa configuration d'origine.

**Mémoriser dans l'ES-9** écrit explicitement le réglage dans la mémoire
**Avec USB** ou **Sans ordinateur**, uniquement après vérification du mix.
Les noms et le mapping Novation restent sur le Mac. Sans cette opération, les
changements du module ne sont pas garantis après extinction.

## Validation et limites

### Charge DSP

La barre d’état et la fenêtre **Configurer MIDI** affichent la charge DSP de
chacun des deux mélangeurs internes, à une décimale. La lecture démarre dès
que les deux ports ES-9 sont disponibles, même en démonstration ou après
**Suspendre** : elle ne modifie aucun réglage ni le trajet audio.
L’application envoie la requête SysEx `0x2B` toutes les deux secondes et
décode la réponse `0x12`, avec le même calcul que l’outil officiel 1.3 :
`(cycles utilisés − base) × 100 / (4096 − base)`.
Le deuxième DSP est indiqué **inactif** lorsque sa base vaut zéro.
Ce pourcentage n’est ni un niveau audio ni la charge CPU du Mac.

Les lectures sont mises en pause pendant les envois de réglages, vérifications
et sauvegardes. Une déconnexion, une réponse invalide ou un délai dépassant
quatre secondes remplace les valeurs par **DSP : —**, avec une explication
visible ; aucune valeur n’est simulée. Les lectures reprennent automatiquement.
La requête et le décodage des deux charges ont été vérifiés sur un ES-9 connecté,
par une lecture MIDI réelle sans changement de configuration.

### Vu-mètres

Le protocole SysEx documenté du firmware 1.3 fournit la configuration, les
coefficients du mélangeur et la charge DSP, mais pas les niveaux audio réels.
Cette version n'affiche donc pas de vu-mètres simulés à partir des faders.
Mesurer les entrées demanderait une capture audio USB côté Mac ; mesurer
réellement toutes les sorties nécessiterait en plus des retours audio ou un
routage d'enregistrement différent. Aucun de ces changements n'est effectué :
le trajet audio et les quatorze canaux d'enregistrement sont préservés.

```sh
swift run MixerCoreTests
bash scripts/test-midi.sh
```

Le runner de tests ne nécessite pas XCTest ni une installation complète de Xcode.
Le test CoreMIDI utilise uniquement deux ports virtuels temporaires et vérifie
un dump SysEx de 2166 octets ainsi que deux messages CC ; aucun matériel n'est modifié.
Les tests couvrent l'allocation des destinations, les gains, les octets SysEx,
le décodage des sauvegardes, le parsing MIDI et le rattrapage. Ils vérifient aussi
la linéarité du gain entre 40 % et 100 %, la courbe inverse sur les 128 valeurs
CC et l'activation du lissage sur les 16 sorties internes.
Ils vérifient également
les huit faders de sortie, les gains combinés entrée/sortie, les solos cumulatifs
et la priorité du mute sur les deux mélangeurs, l'indépendance général/casque,
la banque MIDI des sorties et la migration des anciennes sessions sans
changement de niveau.
Les tests Strip vérifient l'encodage et l'adressage des filtres d'EQ, leur
suivi lors d'une redistribution des entrées, le gain du trim et la migration des
anciennes sessions (trim 0 dB, EQ désactivé).
Les tests de matrice vérifient les 112 liaisons simultanées, les gains indépendants,
les mutes et solos, les limites matérielles, la redistribution sécurisée, les
entrées sans destination et la migration des anciennes destinations exclusives.
Le protocole cible le format de configuration 3 du firmware ES-9 1.3 ; les
autres formats sont refusés avant modification.

Hormis le trajet entrée 1 vers sortie jack 1 décrit ci-dessus, cette première
version doit encore être validée avec un ES-9 et un Launch Control XL MK2
physiques : CoreMIDI et les tests logiciels ne prouvent pas à eux seuls la
compatibilité matérielle.

Références : [manuel ES-9 1.3](https://www.expert-sleepers.co.uk/downloads/manuals/es9_user_manual_1.3.pdf),
[outil officiel 1.3](https://www.expert-sleepers.co.uk/webapps/es9_config_tool_1.3.html).
Le code de l'application est indépendant ; l'outil officiel sert de référence
pour les identifiants des canaux et le format des messages.
