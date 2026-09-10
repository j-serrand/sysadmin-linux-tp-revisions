#!/bin/bash
#
# check-tp.sh — Verification automatique du TP de revisions 1CIEL-IR
# A executer SUR LA VM, en root : sudo ./check-tp.sh
#

SCORE=0
TOTAL=0

VERT="\033[0;32m"
ROUGE="\033[0;31m"
JAUNE="\033[0;33m"
GRAS="\033[1m"
RAZ="\033[0m"

titre() {
    echo
    echo -e "${GRAS}=== $1 ===${RAZ}"
}

# ok <description> <commande...>  -> +1 point si la commande reussit
ok() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    DETAIL=""
    if "$@" >/dev/null 2>&1; then
        echo -e "  [${VERT}OK${RAZ}]     $desc"
        SCORE=$((SCORE + 1))
    else
        echo -e "  [${ROUGE}ECHEC${RAZ}]  $desc"
        # DETAIL est renseigne par certaines fonctions de test (contenu_conforme)
        [ -n "$DETAIL" ] && echo -e "${JAUNE}${DETAIL}${RAZ}"
    fi
}

# pas_ok <description> <commande...>  -> +1 point si la commande ECHOUE
pas_ok() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo -e "  [${ROUGE}ECHEC${RAZ}]  $desc"
    else
        echo -e "  [${VERT}OK${RAZ}]     $desc"
        SCORE=$((SCORE + 1))
    fi
}

# groupe_existe <groupe>
groupe_existe() { getent group "$1" >/dev/null; }

# user_existe <user>
user_existe() { id "$1" >/dev/null 2>&1; }

# user_dans_groupe <user> <groupe>
user_dans_groupe() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }

# perms <chemin> <octal> <proprietaire> <groupe>
perms() {
    local chemin="$1" attendu="$2" prop="$3" grp="$4"
    [ -e "$chemin" ] || return 1
    local reel
    reel=$(stat -c '%a %U %G' "$chemin") || return 1
    [ "$reel" = "$attendu $prop $grp" ]
}

# perms_fichier_attendues <octal_du_dossier>
# Un fichier n'a pas a porter le bit d'execution du dossier : sur un dossier, x
# autorise la traversee, sur un fichier il le rend executable. On accepte donc
# pour chaque triplet la valeur du dossier, ou cette valeur sans le bit x.
# Exemple : dossier 775 -> fichiers 775 ou 664 (et les combinaisons par triplet).
perms_fichier_attendues() {
    local oct="$1"
    local u=${oct:0:1} g=${oct:1:1} o=${oct:2:1}
    local lu lg lo
    for lu in "$u" "$((u & ~1))"; do
        for lg in "$g" "$((g & ~1))"; do
            for lo in "$o" "$((o & ~1))"; do
                echo "$lu$lg$lo"
            done
        done
    done | sort -u
}

# contenu_conforme <repertoire> <octal_du_dossier> <proprietaire> <groupe>
# Verifie que le repertoire n'est pas vide, et que TOUT son contenu (fichiers ET
# sous-dossiers) appartient au bon proprietaire et au bon groupe, avec des
# permissions coherentes. Les ecarts sont listes dans la variable DETAIL.
contenu_conforme() {
    local rep="$1" attendu="$2" prop="$3" grp="$4"
    DETAIL=""
    [ -d "$rep" ] || { DETAIL="le repertoire n'existe pas"; return 1; }

    local nb
    nb=$(find "$rep" -type f 2>/dev/null | wc -l)
    if [ "$nb" -eq 0 ]; then
        DETAIL="aucun fichier dans le repertoire (fichiers non deplaces ?)"
        return 1
    fi

    # Permissions acceptees pour les fichiers (avec ou sans le bit x)
    local ok_fichier
    ok_fichier=$(perms_fichier_attendues "$attendu")

    local chemin type_e mode user group souci
    local mauvais=0
    while IFS='|' read -r chemin type_e mode user group; do
        [ -z "$chemin" ] && continue
        souci=""
        [ "$user" != "$prop" ] && souci="proprietaire=$user (attendu $prop)"
        if [ "$group" != "$grp" ]; then
            [ -n "$souci" ] && souci="$souci, "
            souci="${souci}groupe=$group (attendu $grp)"
        fi
        if [ "$type_e" = "d" ]; then
            # un sous-dossier doit porter exactement les permissions du dossier parent
            if [ "$mode" != "$attendu" ]; then
                [ -n "$souci" ] && souci="$souci, "
                souci="${souci}permissions=$mode (attendu $attendu)"
            fi
        else
            if ! grep -qx "$mode" <<< "$ok_fichier"; then
                [ -n "$souci" ] && souci="$souci, "
                souci="${souci}permissions=$mode (attendu $(tr '\n' '/' <<< "$ok_fichier" | sed 's:/$::'))"
            fi
        fi
        if [ -n "$souci" ]; then
            mauvais=$((mauvais + 1))
            [ "$mauvais" -le 3 ] && DETAIL="${DETAIL}
             -> $chemin : $souci"
        fi
    done < <(find "$rep" -mindepth 1 \( -type f -o -type d \) -exec stat -c '%n|%F|%a|%U|%G' {} + 2>/dev/null |
             sed 's/|directory|/|d|/; s/|regular file|/|f|/; s/|regular empty file|/|f|/')

    if [ "$mauvais" -gt 3 ]; then
        DETAIL="${DETAIL}
             -> ... et $((mauvais - 3)) autre(s) element(s) non conforme(s)"
    fi
    [ "$mauvais" -eq 0 ]
}

echo -e "${GRAS}"
echo "###############################################################"
echo "#   TP de revisions Linux - 1CIEL-IR - Verification           #"
echo "###############################################################"
echo -e "${RAZ}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${ROUGE}Ce script doit etre lance avec sudo : sudo ./check-tp.sh${RAZ}"
    exit 1
fi

# --------------------------------------------------------------------
titre "Mission 5 - Groupes"
for g in gaulois druides guerriers bardes romains; do
    ok "groupe $g existe" groupe_existe "$g"
done

titre "Mission 5 - Utilisateurs"
for u in asterix obelix panoramix assurancetourix jules; do
    ok "utilisateur $u existe" user_existe "$u"
done

titre "Mission 5 - Appartenance aux groupes"
ok "asterix dans gaulois"            user_dans_groupe asterix gaulois
ok "asterix dans guerriers"          user_dans_groupe asterix guerriers
ok "asterix dans sudo"               user_dans_groupe asterix sudo
ok "obelix dans gaulois"             user_dans_groupe obelix gaulois
ok "obelix dans guerriers"           user_dans_groupe obelix guerriers
ok "panoramix dans gaulois"          user_dans_groupe panoramix gaulois
ok "panoramix dans druides"          user_dans_groupe panoramix druides
ok "panoramix dans sudo"             user_dans_groupe panoramix sudo
ok "assurancetourix dans gaulois"    user_dans_groupe assurancetourix gaulois
ok "assurancetourix dans bardes"     user_dans_groupe assurancetourix bardes
ok "jules dans romains"              user_dans_groupe jules romains
pas_ok "jules PAS dans sudo"         user_dans_groupe jules sudo

# --------------------------------------------------------------------
titre "Mission 6 - Repertoires, proprietaires et permissions"
ok "/village/place        775 asterix:gaulois"          perms /village/place  775 asterix gaulois
ok "/village/huttes       750 asterix:gaulois"          perms /village/huttes 750 asterix gaulois
ok "/village/potion       750 panoramix:druides"        perms /village/potion 750 panoramix druides
ok "/village/armes        770 obelix:guerriers"         perms /village/armes  770 obelix guerriers
ok "/village/chants       754 assurancetourix:bardes"   perms /village/chants 754 assurancetourix bardes
ok "/camp-romain          750 jules:romains"            perms /camp-romain    750 jules romains

titre "Mission 6 - Contenu des repertoires (recursivite)"
ok "/village/place  : fichiers presents et conformes"   contenu_conforme /village/place  775 asterix gaulois
ok "/village/potion : fichiers presents et conformes"   contenu_conforme /village/potion 750 panoramix druides
ok "/village/armes  : fichiers presents et conformes"   contenu_conforme /village/armes  770 obelix guerriers
ok "/village/chants : fichiers presents et conformes"   contenu_conforme /village/chants 754 assurancetourix bardes
ok "/camp-romain    : fichiers presents et conformes"   contenu_conforme /camp-romain    750 jules romains

# --------------------------------------------------------------------
titre "Mission 7 - Reseau"

IFACE=$(ip -o -4 route show default | awk '{print $5}' | head -1)
IP_CIDR=$(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -1)
GW=$(ip -o -4 route show default | awk '{print $3}' | head -1)
# Le DNS peut etre declare sur l'interface (Link) ou globalement (Global) :
# on collecte les deux, sinon un DNS correct mais global passe pour absent.
DNS=$( { resolvectl dns "$IFACE" 2>/dev/null; resolvectl status 2>/dev/null | grep -i 'DNS Servers'; } |
       grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | tr '\n' ' ' | sed 's/ $//')
# Repli si resolvectl est absent ou muet
[ -z "$DNS" ] && DNS=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null |
                       awk '{print $2}' | grep -v '^127\.' | sort -u | tr '\n' ' ' | sed 's/ $//')

echo "  Interface : ${IFACE:-inconnue}"
echo "  Adresse   : ${IP_CIDR:-aucune}"
echo "  Passerelle: ${GW:-aucune}"
echo "  DNS       : ${DNS:-aucun}"
echo

# adresse statique attendue : 192.168.{116|117}.2XX/24
ok "adresse en 192.168.116.2XX/24 ou 192.168.117.2XX/24" \
    grep -qE '^192\.168\.11[67]\.2[0-9]{2}/24$' <<< "$IP_CIDR"

# la passerelle doit etre .254 dans le MEME sous-reseau que l'adresse
SALLE=$(cut -d. -f3 <<< "$IP_CIDR")
ok "passerelle = 192.168.$SALLE.254" \
    test "$GW" = "192.168.$SALLE.254"

ok "DNS = 192.168.100.10"          grep -q '192\.168\.100\.10' <<< "$DNS"
ok "DHCP desactive dans netplan"   grep -rqE 'dhcp4:[[:space:]]*(false|no)' /etc/netplan/
ok "passerelle joignable (ping)"   ping -c 2 -W 2 "$GW"

titre "Mission 7 - Utilisateur pigeon"
ok "utilisateur pigeon existe"     user_existe pigeon
pas_ok "pigeon PAS dans sudo"      user_dans_groupe pigeon sudo
ok "serveur SSH actif"             systemctl is-active --quiet ssh

# --------------------------------------------------------------------
echo
echo -e "${GRAS}###############################################################${RAZ}"
if [ "$SCORE" -eq "$TOTAL" ]; then
    COULEUR=$VERT
elif [ "$SCORE" -ge $((TOTAL * 2 / 3)) ]; then
    COULEUR=$JAUNE
else
    COULEUR=$ROUGE
fi
echo -e "${GRAS}   RESULTAT : ${COULEUR}$SCORE / $TOTAL${RAZ}${GRAS} verifications reussies${RAZ}"
echo -e "${GRAS}###############################################################${RAZ}"
echo

if [ "$SCORE" -ne "$TOTAL" ]; then
    echo "Reprenez les points marques [ECHEC] ci-dessus."
    exit 1
fi
echo "Felicitations, appelez l'enseignant pour la validation !"
