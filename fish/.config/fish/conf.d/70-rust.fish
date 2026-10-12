# Rust toolchain (rustup): install.sh installs rustup with --no-modify-path
# so it never writes through stowed configs; wire ~/.cargo/bin into PATH here
# instead. Appended (not prepended) so mise-managed toolchains keep priority.
if test -d "$HOME/.cargo/bin"
    fish_add_path -g "$HOME/.cargo/bin"
end
