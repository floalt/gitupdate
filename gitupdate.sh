#!/bin/bash

SCRIPTPATH=$(dirname "$(readlink -e "$0")")
CONFIG_FILE="$SCRIPTPATH/gitupdate.conf"
OWNER="itflows"



# Prüfen, ob die Konfigurationsdatei existiert

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Fehler: Konfigurationsdatei $CONFIG_FILE nicht gefunden!"
        ### exit 1
    fi

ALL_UPDATES_SUCCESSFUL=true  # Flag für fehlerfreie Updates


# Konfigurationsdatei zeilenweise einlesen

while IFS=";" read -r SCRIPT_FILE SCRIPT_PATH SCRIPT_URL || [[ -n "$SCRIPT_FILE" ]]; do
    
    # Leere Zeilen oder Kommentare überspringen
    [[ -z "$SCRIPT_FILE" || "$SCRIPT_FILE" =~ ^# ]] && continue

    FULL_PATH="$SCRIPT_PATH/$SCRIPT_FILE"
    TMP_FILE="$(mktemp)"
    ETAG_FILE="$FULL_PATH.etag"

    # Überprüfe, ob die Datei existiert
    if [ ! -f "$FULL_PATH" ]; then
        echo "Fehler: Die Datei $FULL_PATH existiert nicht. Abbruch."
        ALL_UPDATES_SUCCESSFUL=false
        continue # überspringe diese Zeile und fahre mit der nächsten fort
    fi

    # Falls vorhanden, lese das alte ETag aus
    if [ -f "$ETAG_FILE" ]; then
        ETAG=$(cat "$ETAG_FILE")
    else
        ETAG=""
    fi

    # Lade Datei nur, wenn sich der ETag geändert hat
    HTTP_RESPONSE=$(curl -s -H "If-None-Match: $ETAG" -w "%{http_code}" -o "$TMP_FILE" "$SCRIPT_URL")

    # Falls der HTTP-Code 200 ist, wurde die Datei geändert → Update speichern
    if [ "$HTTP_RESPONSE" -eq 200 ]; then
        # ETag abrufen
        NEW_ETAG=$(curl -sI "$SCRIPT_URL" | grep -i "etag" | cut -d' ' -f2-)
        if [ -z "$NEW_ETAG" ]; then
            echo "Fehler: Kein ETag von $SCRIPT_URL erhalten."
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # Datei verschieben
        mv "$TMP_FILE" "$FULL_PATH"
        if [ $? -ne 0 ]; then
            echo "Fehler beim Verschieben der Datei nach $FULL_PATH"
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # ETag speichern
        echo "$NEW_ETAG" > "$ETAG_FILE"
        if [ $? -ne 0 ]; then
            echo "Fehler beim Schreiben des ETags in $ETAG_FILE"
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # Berechtigungen & Besitzer setzen
        chmod 754 "$FULL_PATH"
        chown "$OWNER:root" "$FULL_PATH"

        echo "Update für $SCRIPT_FILE durchgeführt."
    
    elif [ "$HTTP_RESPONSE" -eq 304 ]; then
        echo "$SCRIPT_FILE ist aktuell. Kein Update nötig."
        rm "$TMP_FILE"
    
    else
        echo "Fehler beim Abrufen von $SCRIPT_FILE (HTTP-Code: $HTTP_RESPONSE)"
        rm "$TMP_FILE"
        ALL_UPDATES_SUCCESSFUL=false
    fi

done < "$CONFIG_FILE"

# Wenn alle Updates erfolgreich waren, erstelle die leere Datei "lastupdate-done"
if [ "$ALL_UPDATES_SUCCESSFUL" = true ]; then
    touch "$SCRIPTPATH/lastupdate-done"
    echo "Alles erfolgreich. Monitoring-Datei erstellt."
else
    echo "Ein oder mehrere Updates fehlgeschlagen. Keine Monitoring-Datei erstellt."
fi
