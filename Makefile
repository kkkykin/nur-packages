%:
	NIXPKGS_ALLOW_UNFREE=1 nix build ".#$@" --impure --show-trace

clean:
	rm result
