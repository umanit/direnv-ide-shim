# direnv-ide-shim

Binaires shim (`php`, `composer`, …) qui résolvent, à chaque appel, l'environnement `direnv`/Nix du projet dans lequel ils sont lancés, puis délèguent au vrai binaire correspondant.

## Pourquoi

Les projets qui propulsent PHP via un `devShell` Nix (ex. `use flake` dans un `.envrc`) exposent des binaires dont le chemin dans le `/nix/store` change à chaque rebuild (mise à jour de `flake.lock`, garbage collection…). Les IDE comme PhpStorm exigent un chemin d'interpréteur figé et ne le relisent pas dynamiquement : après chaque rebuild, l'interpréteur configuré casse et doit être repointé à la main.

Plus subtil : les intégrations "Quality Tools" de PhpStorm (PHPStan, PHP_CodeSniffer…) n'invoquent même pas l'interpréteur CLI configuré dans les settings — elles exécutent directement le script `vendor/bin/phpstan`/`vendor/bin/phpcs`, en s'appuyant sur son shebang `#!/usr/bin/env php`. Ça exige donc un `php` *littéralement présent sur le `PATH`*, indépendamment de tout interpréteur configuré ailleurs dans l'IDE.

Ce flake fournit un point d'indirection stable : des binaires nommés exactement comme l'outil réel (`php`, `composer`), installés une fois au niveau machine, valables pour **tous** les projets Nix/direnv de la machine — et qui satisfont donc aussi bien la résolution `env php` des shebangs que la configuration explicite d'un interpréteur dans un IDE.

## Fonctionnement

Chaque shim exécute `direnv exec "$PWD" <outil> "$@"`. `direnv` remonte lui-même l'arborescence des dossiers pour trouver le `.envrc` du projet courant — le shim n'a donc besoin de rien savoir de la configuration du projet dans lequel il est appelé. Le `devShell` du projet expose sa propre entrée `bin/` en tête de PATH, donc la résolution retombe sur le vrai binaire du projet, pas sur le shim lui-même.

**Garde-fou anti-boucle** : en dehors de tout projet direnv (pas de `.envrc` trouvé), `direnv exec` ne fait qu'exécuter la commande avec l'environnement courant inchangé — donc une seconde résolution du même nom d'outil retomberait sur ce shim lui-même, à l'infini. Chaque shim pose donc une variable d'environnement au premier passage ; si elle est déjà présente (donc si aucun `.envrc` n'a modifié le `PATH` pour fournir un vrai binaire), il échoue proprement avec un message clair plutôt que de boucler.

Prérequis, par projet cible : `direnv allow` doit avoir été exécuté au moins une fois (comportement standard `direnv`, indépendant de ce shim).

## Installation

### Machine NixOS / home-manager

```nix
inputs.direnv-ide-shim.url = "github:umanit/direnv-ide-shim";
# ...
home.packages = [ inputs.direnv-ide-shim.packages.${pkgs.system}.default ];
```

### Machine avec Nix seul (sans NixOS), ex. Ubuntu

```bash
nix profile install "github:umanit/direnv-ide-shim"
```

Dans les deux cas, `php` / `composer` sont disponibles dans le profil utilisateur — mais le chemin exact dépend de comment home-manager est câblé :

- **home-manager standalone** (`home-manager switch`) : `~/.nix-profile/bin/php`.
- **home-manager en module NixOS** (`useGlobalPkgs = true` / `useUserPackages = true`, ex. via `nh os switch`) : `/etc/profiles/per-user/<utilisateur>/bin/php` — c'est ce dernier cas qui s'applique si `~/.nix-profile/` n'existe pas.
- `nix profile install` (Nix seul, sans NixOS/home-manager) : `~/.nix-profile/bin/php`.

En cas de doute, `command -v php` (une fois le binaire dans le `PATH` du shell) donne le chemin exact à coller dans PhpStorm.

⚠️ Ce paquet place un `php`/`composer` en tête de `PATH` sur toute la machine. Sur une machine qui possède *aussi* un vrai PHP système global (ex. installé via `apt`), en dehors de tout projet Nix/direnv ce shim primera et échouera avec le message d'erreur du garde-fou plutôt que de retomber sur ce PHP système — à garder en tête si ce cas d'usage existe chez vous.

## Configuration PhpStorm (par projet, une seule fois)

- `Settings › PHP › CLI Interpreters` → chemin vers `php` (voir ci-dessus pour le localiser).
- `Settings › PHP › Composer › Executable` → `composer`.
- Rien à faire côté PHPStan/PHP_CodeSniffer : une fois `php` présent sur le `PATH` global, leur résolution `#!/usr/bin/env php` fonctionne d'elle-même.

## Ajouter un outil

Ajouter son nom à la liste `tools` dans `flake.nix` (ex. `"symfony"`), rebuild — `symfony` apparaît automatiquement.
