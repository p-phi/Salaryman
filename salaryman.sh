      echo "  [$name] $(jq -r 'tostring' <<<"$args")" >&2
      result=$(run_tool "$name" "$args")
      messages=$(jq -c --arg name "$name" --arg content "$result" \
        '. + [{role:"tool", name:$name, content:$content}]' <<<"$messages")
    done
  done

  echo "error: max iterations ($MAX_ITERATIONS) reached" >&2
  exit 1
}

main