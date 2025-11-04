Small program to manage collecting all cards of a given pokemon.

Usage:
1. Compile the program with `zig build`. You'll find the binary under `zig-out/bin/collector`, move it whenever you want
1. Mark a card as owned with `collector add --id <card_id>` (back to missing with `collector rm --id <card_id>`)
1. Display missing cards' information with `collector ls --name <pokemon_name>`
