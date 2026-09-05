# Architecture — App de transfert de fichiers P2P chiffré de bout en bout

## Contexte et objectif du projet

Créer une application (mobile + desktop + web) permettant à deux utilisateurs de
s'échanger un fichier en **peer-to-peer direct**, chiffré de bout en bout,
**sans jamais stocker le fichier sur un serveur**, et sans dépendance à des
services cloud tiers type WeTransfer (qui font transiter les fichiers par leurs
serveurs) ni à des GAFAM.

Inspiration initiale : [croc](https://github.com/schollz/croc) et
[magic-wormhole](https://github.com/magic-wormhole/magic-wormhole), avec la
distinction importante que croc utilise un serveur relais par défaut (les
données chiffrées transitent dessus), alors que l'objectif ici est le **P2P
direct sans relais**, y compris en cas d'échec de connexion (pas de fallback
silencieux).

## Principes non négociables

1. **Aucun serveur ne stocke ni ne relaie jamais le contenu d'un fichier.**
2. **Pas de serveur TURN / pas de fallback relais.** Si la connexion P2P
   directe échoue, une erreur explicite est affichée à l'utilisateur plutôt
   qu'un repli silencieux qui trahirait la promesse de confidentialité et
   d'architecture.
3. **Minimum de dépendances tierces.** Toute l'infra nécessaire est
   auto-hébergée sur un unique VPS via Docker. Zéro service GAFAM (y compris
   pour STUN).
4. **Chiffrement de bout en bout**, avec une couche applicative en plus du
   chiffrement natif de WebRTC (DTLS), pour ne pas dépendre de la confiance
   dans le serveur de signaling.
5. **Serverless au sens "pas de stockage fichier"**, mais avec un petit
   service de signaling stateless nécessaire (WebRTC ne peut pas se passer
   d'une poignée de main initiale entre pairs).

## Stack technique retenue

- **Flutter** pour le client, cible unique couvrant : iOS, Android, Web,
  Windows, macOS, Linux. Choisi plutôt que React Native pour la cohérence
  du support web (contrairement à RN où le web reste secondaire) et le
  support desktop natif de premier niveau.
- **Dart** également côté serveur de signaling, pour permettre le partage de
  code (classes de messages, sérialisation) entre client et serveur dans un
  même mono-repo.
- **flutter_webrtc** comme binding WebRTC (wrap libwebrtc, disponible sur
  toutes les cibles Flutter).
- **Docker** pour le déploiement du signaling + STUN sur un VPS unique.

---

## 1. Mono-repo — structure

Géré avec **Melos** (outil standard pour gérer plusieurs packages Dart/Flutter
interdépendants dans un seul repo : bootstrap des liens locaux, scripts
communs, versioning coordonné).

```
p2p-transfer/
├── melos.yaml
├── docker-compose.yml
├── Caddyfile
├── packages/
│   ├── shared/                  # Package Dart pur, partagé client+serveur
│   │   ├── lib/
│   │   │   ├── src/
│   │   │   │   ├── messages/    # Classes de messages signaling (SDP, ICE, offer/answer)
│   │   │   │   ├── codes/       # Génération/validation du code de connexion (mots lisibles)
│   │   │   │   └── crypto/      # Couche PAKE / dérivation de clé
│   │   │   └── shared.dart
│   │   └── pubspec.yaml
│   │
│   ├── signaling_server/        # Package Dart pur (pas Flutter), serveur WebSocket
│   │   ├── bin/
│   │   │   └── server.dart
│   │   ├── lib/src/
│   │   │   ├── room_manager.dart
│   │   │   └── ws_handler.dart
│   │   ├── Dockerfile
│   │   └── pubspec.yaml         # dépend de shared (path: ../shared)
│   │
│   └── app/                     # Package Flutter (mobile + desktop + web)
│       ├── lib/src/
│       │   ├── webrtc/          # Wrapping flutter_webrtc
│       │   ├── signaling/       # Client WebSocket vers signaling_server
│       │   ├── transfer/        # Chunking fichier, progress, streaming disque
│       │   └── ui/
│       └── pubspec.yaml         # dépend de shared (path: ../shared)
```

**Pourquoi cette découpe** :
- `shared` ne dépend de rien de spécifique à Flutter ni au serveur → pur Dart,
  importable des deux côtés.
- `signaling_server` reste un package Dart **pur** (pas Flutter) → plus léger
  à compiler en AOT pour Docker.
- `app` isolé comme unique package Flutter → Melos gère la résolution des
  `path:` dependencies automatiquement.

---

## 2. Format des messages (`shared/messages`)

Le serveur de signaling ne comprend jamais le contenu WebRTC (SDP/ICE), il
**relaie** des enveloppes. Deux catégories : messages de gestion de room
(client ↔ serveur) et messages relayés entre pairs (payload opaque pour le
serveur).

Utiliser un `sealed class` Dart pour l'enveloppe générique permet un pattern
matching exhaustif (`switch`) côté réception, des deux côtés.

### Messages de gestion de room

- `JoinRoom { code: String }` — un client rejoint avec le code (mots lisibles,
  ex. "renard-bureau-lampe-19")
- `RoomJoined { peerId: String }` — confirmation ; le serveur attribue un
  `peerId` temporaire, pas de compte ni d'identité persistante
- `PeerConnected {}` — signale que l'autre pair vient de rejoindre, déclenche
  le début du handshake WebRTC côté offreur
- `RoomError { reason: RoomErrorReason }` — code déjà pris, room pleine (max 2
  pairs), room expirée...
- `PeerDisconnected {}` — l'autre pair a fermé la connexion avant la fin du
  handshake

### Messages de relais WebRTC (payload opaque pour le serveur)

- `Offer { sdp: String }`
- `Answer { sdp: String }`
- `IceCandidate { candidate: String, sdpMLineIndex: int, sdpMid: String? }`

Le serveur les reçoit encapsulés dans `RelayMessage { targetPeerId: String,
payload: String }` — il ne désérialise que l'enveloppe extérieure pour savoir
où relayer, jamais le contenu WebRTC en détail.

### Sérialisation

`toJson()`/`fromJson()` sur chaque classe. Pour éviter les bugs de désync,
envisager `freezed` + `json_serializable` (génération automatique à partir
d'une définition déclarative).

### Sur le code de connexion

Le code sert uniquement de clé de matching pour le serveur. Le vrai secret
cryptographique (pour dériver la clé de chiffrement applicatif E2E) doit être
dérivé **côté client uniquement**, de sorte qu'un signaling server compromis
ne puisse pas compromettre la confidentialité (voir section chiffrement).

### Génération du code lisible

Wordlist embarquée en asset JSON (2000-4000 mots), tirage de 3-4 mots via
`Random.secure()`. Avec 4000 mots sur 3 mots : ~64 milliards de combinaisons,
largement suffisant vu la fenêtre de vie courte (30-60s) et le rate-limiting
côté serveur.

---

## 3. `room_manager.dart` — logique serveur

**Rôle** : associer exactement 2 clients partageant le même code, sans
persistance ni historique.

```dart
class RoomManager {
  final Map<String, Room> _rooms = {};
}

class Room {
  final String code;
  WebSocketChannel? peerA;
  WebSocketChannel? peerB;
  final DateTime createdAt;
}
```

Tout en mémoire (pas de DB) — acceptable vu que les rooms sont éphémères
(quelques secondes à quelques minutes, le temps du handshake).

### Cycle de vie d'une room

1. **Création implicite** : premier client avec un code inédit → `Room` créée,
   assigné à `peerA`, réponse `RoomJoined`.
2. **Complétion** : deuxième client avec le même code → assigné à `peerB`, les
   deux reçoivent le signal pour démarrer le handshake WebRTC.
3. **Rejet** : troisième client sur le même code → `RoomError(codeAlreadyInUse)`.
   Une room ne contient jamais plus de 2 pairs.
4. **Relais** : tout `RelayMessage` reçu d'un pair est transmis tel quel à
   l'autre pair de la même room (forwarding pur, zéro logique métier sur le
   contenu).
5. **Nettoyage** : dès qu'un pair ferme sa WebSocket, la `Room` est détruite
   immédiatement.
6. **Expiration de sécurité** : un `Timer` par room la détruit automatiquement
   après un délai court (30-60s) si elle n'a jamais atteint 2 pairs, pour
   éviter l'accumulation de rooms orphelines.

### Concurrence

Dart étant single-threaded par isolate, pas de race condition classique sur
`_rooms` tant que le traitement des messages reste dans le même isolate — pas
besoin de locks.

### Sécurité — rate-limiting

Le `room_manager` doit rate-limiter les tentatives de `JoinRoom` avec un code
invalide (par IP ou fenêtre de temps), sinon un attaquant pourrait bruteforcer
un code actif pendant sa fenêtre de vie et s'insérer dans une room à la place
du destinataire légitime.

---

## 4. Chiffrement de bout en bout applicatif

### Pourquoi une couche en plus de DTLS

WebRTC chiffre déjà le DataChannel via DTLS, mais cela protège le *transport*,
pas la *confiance dans l'identité du pair*. Le point faible potentiel est le
signaling server : s'il est compromis, il pourrait théoriquement s'insérer en
attaque man-in-the-middle pendant l'échange SDP/ICE. Un PAKE
(Password-Authenticated Key Exchange) élimine ce risque en dérivant une clé
symétrique à partir du code partagé, sans jamais faire transiter ce secret ou
une clé en clair.

### Option idéale : SPAKE2

Utilisé par croc et magic-wormhole. Principe : les deux clients connaissent le
même secret faible (le code), chacun génère une contribution publique
combinant clé éphémère + secret, l'échange de ces contributions (qui ne
révèlent rien seules) permet aux deux bouts de calculer indépendamment la même
clé de session forte.

**Limite pratique** : pas de lib SPAKE2 mainstream en Dart pur identifiée à ce
jour. Il faudrait soit binder une implémentation existante (libsodium a des
primitives proches), soit implémenter le protocole depuis la spec (RFC 9382)
— ce qui demande de la rigueur crypto et une revue dédiée.

### Option alternative retenue par défaut : X25519 + HKDF

Moins "pur PAKE" que SPAKE2, mais réalisable proprement en Dart via le package
`cryptography` (supporte AES-GCM, X25519, HKDF nativement, sans dépendance
native compliquée).

**Flux** :
1. Génération du code → dérivation locale d'un secret initial
2. Handshake WebRTC classique (Offer/Answer/ICE) en parallèle
3. Une fois le DataChannel ouvert, échange des clés publiques X25519 **à
   travers ce DataChannel** (déjà protégé par DTLS, couche applicative
   ajoutée par-dessus)
4. Dérivation HKDF → clé AES-256-GCM de session
5. Chaque chunk de fichier est chiffré avec cette clé avant envoi

**⚠️ Point de risque identifié et non résolu à ce stade** : une implémentation
crypto maison peut contenir des erreurs subtiles (mauvais ordre de dérivation,
nonce réutilisé en AES-GCM, etc.) qui annulent silencieusement la protection,
sans qu'aucun test fonctionnel ne le révèle. **Cette partie nécessite une
revue par quelqu'un d'expérimenté en cryptographie avant d'être considérée
comme fiable en production.**

---

## 5. Client Flutter — `webrtc/`

### Établissement de connexion

```dart
class WebRTCConnection {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;

  Future<void> initialize({required bool isInitiator}) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:ton-serveur.example.com:3478'},
        // pas de serveur TURN — décision assumée, voir section "Risques"
      ]
    };
    _pc = await createPeerConnection(config);

    if (isInitiator) {
      _dataChannel = await _pc!.createDataChannel(
        'file-transfer',
        RTCDataChannelInit()..ordered = true,
      );
      _setupDataChannelHandlers(_dataChannel!);
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      // envoyer offer.sdp via signaling
    } else {
      _pc!.onDataChannel = (channel) {
        _dataChannel = channel;
        _setupDataChannelHandlers(channel);
      };
    }

    _pc!.onIceCandidate = (candidate) {
      // envoyer candidate via signaling
    };

    _pc!.onIceConnectionState = (state) {
      // instrumenter ici pour les métriques (voir section 8)
    };
  }
}
```

Un seul pair (l'initiateur, celui qui génère le code) crée le DataChannel ;
l'autre le reçoit passivement via `onDataChannel`.

### Chunking et transfert de fichier

Contraintes des DataChannels WebRTC :
- Taille de message limitée (~256 KB max conseillé par chunk, marge de
  sécurité SCTP)
- Gestion du `bufferedAmount` nécessaire pour éviter de saturer le buffer
  d'envoi (backpressure)

**Important** : le streaming se fait chunk par chunk en continu (pas de
confirmation/validation individuelle par chunk qui introduirait de la latence
et casserait le débit) — mais avec **écriture disque progressive** côté
réception, jamais d'accumulation complète en mémoire quand la plateforme le
permet (voir section 6).

```dart
class FileSender {
  static const chunkSize = 16 * 1024; // 16 KB
  static const bufferThreshold = 1024 * 1024; // 1 MB

  Future<void> sendFile(File file, RTCDataChannel channel, SecretKey sessionKey) async {
    final stream = file.openRead();
    final totalSize = await file.length();

    await channel.send(RTCDataChannelMessage(jsonEncode({
      'type': 'file-meta', 'name': file.path.split('/').last, 'size': totalSize,
    })));

    await for (final chunk in stream.transform(ChunkTransformer(chunkSize))) {
      while (channel.bufferedAmount != null && channel.bufferedAmount! > bufferThreshold) {
        await Future.delayed(Duration(milliseconds: 50));
      }
      final encrypted = await _encryptChunk(chunk, sessionKey);
      await channel.send(RTCDataChannelMessage.fromBinary(encrypted));
    }

    await channel.send(RTCDataChannelMessage(jsonEncode({'type': 'file-end'})));
  }
}
```

```dart
class FileReceiver {
  // Mobile/desktop : écrire directement sur disque via IOSink en mode append,
  // jamais accumuler en mémoire.
  // Web (Chrome/Edge) : idem via File System Access API.
  // Web (Safari/Firefox) : accumulation en RAM par nécessité (voir section 6).

  void onMessage(RTCDataChannelMessage message, SecretKey sessionKey) async {
    if (message.isBinary) {
      final decrypted = await _decryptChunk(message.binary, sessionKey);
      // écrire `decrypted` directement sur le sink de destination
      // notifier la progress bar UI
    } else {
      final json = jsonDecode(message.text);
      if (json['type'] == 'file-meta') {
        // initialiser le sink de destination avec nom/taille attendus
      } else if (json['type'] == 'file-end') {
        // fermer le sink, finaliser
      }
    }
  }
}
```

---

## 6. Gestion du stockage par plateforme

| Plateforme | Mécanisme | Streaming disque | Limite fichier |
|---|---|---|---|
| iOS / Android | `dart:io File`, écriture via `IOSink` en append | ✅ Oui | Aucune (dépend du stockage device) |
| Windows / macOS / Linux (desktop) | `dart:io File`, identique au mobile | ✅ Oui | Aucune |
| Web (Chrome/Edge) | File System Access API (`showSaveFilePicker` + `FileSystemWritableFileStream`) | ✅ Oui | Aucune |
| Web (Safari/Firefox) | Accumulation en `Blob` mémoire, téléchargement déclenché à la fin | ❌ Non | Limitée (RAM du device/navigateur), à définir précisément et communiquer clairement à l'utilisateur |

**Décision prise** : le web reste un point d'entrée "zéro install, teste tout
de suite", avec un message explicite sur Safari/Firefox recommandant l'app
desktop pour les fichiers volumineux. Le desktop (Windows/macOS/Linux, cible
Flutter native) devient l'option de référence pour les gros transferts sans
aucune limite, exactement comme le mobile.

### Réception côté utilisateur

- Mobile : proposer "Enregistrer" (`path_provider`) ou "Partager vers..."
  (`share_plus`)
- Desktop : écriture directe, dialogue natif de sélection de dossier
- Web : téléchargement navigateur classique (Blob + lien caché, ou write
  stream progressif si API supportée)

### Vérification d'intégrité

Afficher un hash SHA-256 du fichier reçu vs envoyé, pour une confirmation
visuelle de cohérence à l'utilisateur.

---

## 7. Infrastructure — Docker (VPS unique, zéro GAFAM)

### Décision : pas de TURN, pas de fallback relais

Conséquence directe du principe "aucun serveur ne relaie jamais un fichier" :
TURN (Traversal Using Relays around NAT) est par définition un relais — si un
fichier passe par TURN, il transite physiquement sur ce serveur (même s'il
reste chiffré de bout en bout, donc illisible par le serveur). Ce compromis a
été explicitement écarté : en cas d'échec de connexion P2P directe, l'app
affiche une erreur claire plutôt qu'un repli silencieux.

### Décision : STUN auto-hébergé, pas de service Google

STUN est un protocole simple et stateless (RFC 5389) : découverte d'IP/port
public, aucune donnée sensible transportée, coût de ressources négligeable
(pas de relais de bande passante contrairement à TURN). Auto-hébergé via
`coturn` en mode STUN uniquement (sans les fonctionnalités de relais TURN),
ce qui évite la grosse plage de ports UDP et le `network_mode: host`
nécessaires pour TURN complet.

### `docker-compose.yml`

```yaml
services:
  signaling:
    build: ./packages/signaling_server
    ports:
      - "8080:8080"
    restart: unless-stopped

  stun:
    image: coturn/coturn:latest
    ports:
      - "3478:3478/udp"
    restart: unless-stopped
    command: ["-n", "--stun-only", "--listening-port=3478"]

  caddy:
    image: caddy:latest
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
    restart: unless-stopped
```

### `signaling_server/Dockerfile` (multi-stage, compilation AOT)

```dockerfile
# Stage 1 : build
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2 : runtime minimal
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/bin/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

Résultat : image finale de quelques dizaines de Mo, démarrage quasi
instantané (binaire natif AOT, pas de runtime Dart complet embarqué).

### Caddy (reverse proxy + TLS)

Gère automatiquement le certificat Let's Encrypt et le WSS (WebSocket
sécurisé) devant `signaling`, cohérent avec l'objectif de friction
opérationnelle minimale.

---

## 8. Client desktop — spécificités `flutter_webrtc`

Flutter supporte nativement Windows, macOS, Linux comme cibles de
compilation — pas un plugin ni un hack, un vrai target officiel du framework.
`flutter_webrtc` embarque des binaires natifs précompilés de libwebrtc pour
chaque plateforme desktop, téléchargés automatiquement au build (pas besoin
de compiler libwebrtc soi-même).

### Points spécifiques par OS

- **Linux** : nécessite les libs système standards des prérequis Flutter
  Linux desktop (`libgtk-3-dev`, dépendances GStreamer selon version) — rien
  de spécifique à WebRTC en plus.
- **macOS** : signature de code (`codesign`) requise pour distribution hors
  App Store, avec entitlements réseau à déclarer explicitement dans le
  fichier `.entitlements`.
- **Windows** : attention au firewall Windows qui peut bloquer les connexions
  UDP entrantes par défaut — prévoir un message explicatif avant que Windows
  n'affiche sa popup native "Autoriser l'accès réseau", pour ne pas perdre
  l'utilisateur.

### Accès fichier natif

`dart:io File` fonctionne sans sandbox sur desktop, exactement comme mobile —
le code de la couche `transfer/` (écriture streaming) peut être **partagé
tel quel entre mobile et desktop**. Seule la couche web nécessite une
implémentation différente (détection de plateforme via `kIsWeb`).

### UI spécifique desktop

Drag & drop de fichier depuis l'explorateur système (package `desktop_drop`),
en complément ou remplacement du file picker classique — correspond mieux
aux habitudes desktop.

---

## 9. UI Flutter — écrans

### Écran 1 — Accueil

Deux boutons : "Envoyer un fichier" / "Recevoir un fichier".

### Écran 2a — Envoyer (générer le code)

1. Sélection du fichier (`file_picker`, cross-platform)
2. Génération locale du code lisible (wordlist embarquée)
3. Connexion au signaling, `JoinRoom{code}`, `isInitiator: true`
4. Affichage du code en gros + QR code encodant ce code (`qr_flutter`), pour
   éviter la saisie manuelle
5. État "en attente de connexion..." jusqu'à `PeerConnected`

### Écran 2b — Recevoir (saisir/scanner le code)

1. Saisie manuelle ou scan du QR (`mobile_scanner` — attention au support
   caméra variable selon navigateurs sur web)
2. `JoinRoom{code}`, `isInitiator: false`
3. Attente passive de l'`Offer` WebRTC dès `RoomJoined`

### Écran 3 — Transfert en cours

- Barre de progression (`chunks envoyés/reçus × chunkSize / totalSize`)
- Débit instantané (octets/seconde sur fenêtre glissante)
- États explicites : "Connexion..." → "Négociation sécurisée..." (PAKE) →
  "Transfert..." → "Terminé"
- **État d'échec explicite** : "Connexion directe impossible sur ce réseau"
  si ICE échoue, sans tentative de repli
- Bouton d'annulation propre (fermeture DataChannel + RTCPeerConnection)

### Écran 4 — Fin de transfert

- Mobile : "Enregistrer" ou "Partager vers..."
- Web : téléchargement auto déclenché
- Affichage du hash SHA-256 pour vérification d'intégrité visuelle

### State management

`Riverpod` ou `Bloc` recommandé pour exposer l'état de connexion WebRTC de
façon réactive à travers les écrans (à trancher selon préférences déjà
établies sur d'autres projets).

---

## 10. Instrumentation — taux de succès ICE sans TURN

**Objectif** : mesurer, sans fallback TURN, quelle proportion de connexions
échoue réellement dans des conditions réseau variées — donnée qui validera ou
invalidera la viabilité du choix "zéro relais" dans la pratique.

### Métriques côté client

```dart
enum ConnectionOutcome { directSuccess, iceFailed, timeout, userCancelled }

class ConnectionMetrics {
  final ConnectionOutcome outcome;
  final Duration timeToConnect;
  final String? networkType; // wifi / cellular / ethernet, via connectivity_plus
  final int iceCandidatesGathered;
  final String candidateTypeUsed; // host / srflx — jamais 'relay' vu l'absence de TURN
}
```

### Récupération technique

`RTCPeerConnection.onIceConnectionState` (transitions `checking` →
`connected`/`failed`) et `getStats()` pour le détail des candidats ICE
utilisés (`candidateType`), permettant de confirmer si la connexion s'est
faite en direct (`host`) ou via STUN (`srflx`, toujours direct, juste avec
découverte d'adresse assistée).

### Anonymisation stricte

Aucune donnée personnelle ni identifiante dans les métriques : pas d'IP, pas
de code de room, pas d'identifiant fichier. Juste un événement anonyme
agrégé type `{outcome: iceFailed, networkType: cellular, timestamp: ...}`.

### Collecte

Endpoint HTTP minimal ajouté au `signaling_server` (`POST /metrics`,
fire-and-forget), logs structurés agrégeables a posteriori (grep/jq, ou outil
léger type Loki pour dashboard).

---

## 11. Risques identifiés (par priorité)

1. **Taux réel de succès du P2P direct sans TURN** — risque n°1, à mesurer
   dès le premier prototype réel (le chiffre "10-20% de fallback nécessaire"
   est une estimation générale non fiable pour ce use case précis). C'est la
   donnée qui conditionne la viabilité pratique de l'architecture choisie.
   *(Décision prise : assumé, pas de fallback — voir section 7.)*
2. **Fiabilité du DataChannel sur mobile en arrière-plan** — iOS notamment
   throttle/coupe agressivement les connexions réseau en arrière-plan ; un
   transfert long peut échouer silencieusement si l'utilisateur switch d'app.
   À gérer soit par tâches en arrière-plan natives (complexe, différent
   iOS/Android), soit en communiquant clairement la contrainte à l'utilisateur.
3. **Limite mémoire côté web pour Safari/Firefox** — accumulation RAM
   inévitable sans File System Access API. Nécessite une limite de taille
   fichier définie et communiquée, avec incitation vers l'app desktop.
   *(Mitigé par la stratégie desktop-first pour les gros fichiers.)*
4. **Comportement de `flutter_webrtc` sur web vs natif** — support web
   historiquement en retrait par rapport au natif sur certaines APIs (stats
   de connexion, renégociation). À valider tôt avec un prototype cross-
   plateforme réel, pas uniquement via la documentation.
5. **Sécurité du code de room (bruteforce)** — nécessite un rate-limiting
   strict côté `room_manager`, sinon un attaquant pourrait bruteforcer un
   code actif pendant sa fenêtre de vie (30-60s).
6. **Robustesse de l'implémentation crypto maison** (X25519+HKDF) — risque le
   plus insidieux : une erreur subtile peut annuler silencieusement la
   protection sans que les tests fonctionnels le révèlent. **Revue par un
   expert crypto nécessaire avant mise en production.**
7. **Firewall Windows / permissions desktop** — popups natives à anticiper
   dans l'UX plutôt que de laisser l'utilisateur découvrir le blocage sans
   contexte.

---

## 12. Décisions actées (résumé)

- ✅ Flutter pour toutes les cibles (mobile, desktop, web)
- ✅ Dart également côté serveur de signaling, mono-repo via Melos
- ✅ Signaling minimal, stateless, en mémoire, auto-hébergé en Docker
- ✅ **Pas de TURN, pas de fallback relais** — échec explicite affiché à
  l'utilisateur en cas d'échec ICE
- ✅ **STUN auto-hébergé** (coturn en mode `--stun-only`) — zéro dépendance
  GAFAM dans toute la stack
- ✅ Chiffrement E2E applicatif en plus de DTLS (X25519+HKDF par défaut, en
  attente de revue crypto ; SPAKE2 resterait l'option idéale si une
  implémentation Dart fiable devient disponible)
- ✅ Desktop natif comme cible prioritaire pour les gros fichiers (résout
  intégralement la limite mémoire web sur Safari/Firefox)
- ✅ Web conservé comme point d'entrée "zéro install", avec limite de taille
  assumée et communiquée sur Safari/Firefox
- ✅ Écriture disque progressive chunk par chunk (jamais d'accumulation
  complète en mémoire, sauf contrainte plateforme incontournable)
- ⏳ À trancher : seuil de taille fichier exact pour le mode web dégradé
- ⏳ À mesurer : taux réel d'échec ICE en conditions réelles (prototype)
- ⏳ À faire : revue crypto dédiée avant implémentation définitive du
  chiffrement applicatif

---

## 13. Prochaine étape suggérée

Prototype minimal jetable, scope réduit à :
- `signaling_server` + `room_manager` basique
- STUN auto-hébergé
- Handshake WebRTC brut (Offer/Answer/ICE), sans UI ni chiffrement, juste
  échange d'un message "hello" entre deux clients
- Instrumentation du taux de succès ICE dès cette étape

Objectif : valider concrètement le NAT traversal réel et la mécanique de
signaling avant d'investir dans le reste (chunking, chiffrement, UI complète).
