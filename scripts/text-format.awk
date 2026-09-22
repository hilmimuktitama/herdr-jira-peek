# Shared readable text wrapping and semantic styling for issue detail output.
# Inputs are plain logical lines; width/style values are supplied via awk -v
# by render.sh and the customization preview.
function display_length(text,    i, ch, total, advance) {
  total = 0
  for (i = 1; i <= length(text); i++) {
    ch = substr(text, i, 1)
    if (ch == "\t") {
      advance = 8 - (total % 8)
      total += advance
    } else {
      total++
    }
  }
  return total
}

function fit_chars(text, limit,    i, piece) {
  if (limit < 1) return 0
  piece = ""
  for (i = 1; i <= length(text); i++) {
    piece = piece substr(text, i, 1)
    if (display_length(piece) > limit) return i - 1
  }
  return length(text)
}

function has_non_ascii(text) {
  return text ~ /[^\001-\177]/
}

function is_heading(text,    i,n,part,colon,configured) {
  if (NR <= 2 || text ~ /^#{1,6} / || text == "Description" || text ~ /^Comments \([0-9]+\)$/)
    return 1
  n = split(labels, configured, ",")
  for (i = 1; i <= n; i++) {
    colon = index(configured[i], ":")
    if (colon > 1) {
      part = substr(configured[i], colon + 1)
      if (text == part || index(text, part " (") == 1) return 1
    }
  }
  return 0
}

function emit(text,    styled) {
  styled = text
  if (style && is_heading(text) && bold != "")
    styled = bold text reset
  printf "%s\n", styled
  output_count++
}

{
  line = $0
  if (line == "") {
    emit("")
    next
  }

  if (display_length(line) <= width) {
    emit(line)
    next
  }

  indent_length = 0
  while (indent_length < length(line) \
     && substr(line, indent_length + 1, 1) ~ /[ \t]/)
    indent_length++
  indent = substr(line, 1, indent_length)
  rest = substr(line, indent_length + 1)
  first_prefix = indent
  continuation_prefix = indent

  if (substr(rest, 1, 2) == "> ") {
    first_prefix = indent "> "
    continuation_prefix = first_prefix
    rest = substr(rest, 3)
  } else if (substr(rest, 1, 1) ~ /[-*+]/ \
     && substr(rest, 2, 1) ~ /[ \t]/) {
    first_prefix = indent substr(rest, 1, 2)
    continuation_prefix = indent "  "
    rest = substr(rest, 3)
  } else {
    hash_count = 0
    while (substr(rest, hash_count + 1, 1) == "#") hash_count++
    if (hash_count > 0 && substr(rest, hash_count + 1, 1) ~ /[ \t]/) {
      first_prefix = indent substr(rest, 1, hash_count + 1)
      continuation_prefix = indent
      for (i = 1; i <= hash_count + 1; i++) continuation_prefix = continuation_prefix " "
      rest = substr(rest, hash_count + 2)
    }
  }

  if (display_length(first_prefix) >= width) {
    first_prefix = ""
    continuation_prefix = ""
  } else if (display_length(continuation_prefix) >= width) {
    continuation_prefix = ""
  }

  current = first_prefix
  pending = ""
  has_content = 0
  forced_line = 0
  word = ""
  pos = 1
  while (pos <= length(rest)) {
    ch = substr(rest, pos, 1)
    if (ch ~ /[ \t]/) {
      separator = ch
      pos++
      while (pos <= length(rest) && substr(rest, pos, 1) ~ /[ \t]/) {
        separator = separator substr(rest, pos, 1)
        pos++
      }
      pending = separator
      continue
    }

    word = ch
    pos++
    while (pos <= length(rest) && substr(rest, pos, 1) !~ /[ \t]/) {
      word = word substr(rest, pos, 1)
      pos++
    }

    if (has_content && display_length(current pending word) > width) {
      emit(current)
      current = continuation_prefix
      has_content = 0
      pending = ""
    }
    if (!has_content) pending = ""

    while (length(word) > 0) {
      if (has_non_ascii(word) && \
        display_length(word) > width - display_length(current)) {
        if (display_length(word) <= width) {
          current = word
          emit(current)
        } else {
          if (has_content) current = current pending
          current = current word
          emit(current)
        }
        current = continuation_prefix
        has_content = 0
        pending = ""
        word = ""
        forced_line = 1
        continue
      }
      available = width - display_length(current)
      piece_length = fit_chars(word, available)
      if (piece_length < 1) {
        emit(current)
        current = continuation_prefix
        has_content = 0
        pending = ""
        continue
      }
      if (has_content) current = current pending
      current = current substr(word, 1, piece_length)
      word = substr(word, piece_length + 1)
      pending = ""
      has_content = 1
      if (length(word) > 0) {
        emit(current)
        current = continuation_prefix
        has_content = 0
      }
    }
  }

  if (has_content)
    emit(current)
  else if (display_length(line) > width && !forced_line)
    emit("")
}
