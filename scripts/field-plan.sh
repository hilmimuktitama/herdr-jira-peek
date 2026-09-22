# Derive API requests from validated presentation preferences. Sourced only.
# shellcheck disable=SC2034 # Callers consume the derived request values.
# A stable sorted union lets ordering, labels and text style reuse cached detail.
DETAIL_FIELDS=$(printf '%s\n' "summary,$PICKER_FIELDS,$PREVIEW_FIELDS,$READER_FIELDS" \
  | tr ',' '\n' | LC_ALL=C sort -u | awk 'NF && $0 != "link" && $0 != "comments" { if (n++) printf ","; printf "%s", $0 }')
FETCH_COMMENTS=0
case ",$PREVIEW_FIELDS,$READER_FIELDS," in *,comments,*) FETCH_COMMENTS=1 ;; esac
FIELD_REQUEST_SIGNATURE="v1:$DETAIL_FIELDS:comments=$FETCH_COMMENTS"
LEGACY_FIELD_REQUEST=0
if [ "$DETAIL_FIELDS" = 'assignee,description,status,summary,updated' ] && [ "$FETCH_COMMENTS" = 1 ]; then
  LEGACY_FIELD_REQUEST=1
fi
if [ "$PICKER_FIELDS" = 'status,summary' ]; then
  # Preserve the established default batch request for existing installations.
  METADATA_FIELDS=summary,status,assignee,updated
else
  METADATA_FIELDS=$(printf '%s\n' "summary,$PICKER_FIELDS" | tr ',' '\n' \
    | awk 'NF && !seen[$0]++ { if (n++) printf ","; printf "%s", $0 }')
fi
