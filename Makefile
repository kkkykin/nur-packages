%:
	nix build ".#$@" --show-trace

clean:
	rm result
