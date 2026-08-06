#!/usr/bin/env python3
import os
import sys
import shutil
import datetime
import subprocess

def run():
    date_str = datetime.date.today().strftime("%Y%m%d")
    home = os.path.expanduser("~")
    backup_dir = os.path.join(home, ".config", f"doom-emacs-backup-{date_str}")
    repo_dir = os.path.expanduser("~/Projetos/emacsConfig/MyEmacs")
    target_emacs_dir = os.path.join(home, ".config", "emacs")
    vanilla_emacs_dir = os.path.join(home, ".config", "emacs-vanilla")
    doom_dir = os.path.join(home, ".config", "doom")
    local_share_doom = os.path.join(home, ".local", "share", "doom")
    emacs_d = os.path.join(home, ".emacs.d")

    print(f"=== Phase 1: Creating Backup in {backup_dir} ===")
    os.makedirs(backup_dir, exist_ok=True)
    if os.path.exists(doom_dir):
        dest = os.path.join(backup_dir, "doom")
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(doom_dir, dest)
        print(f"Backed up {doom_dir} -> {dest}")
    if os.path.exists(target_emacs_dir):
        dest = os.path.join(backup_dir, "emacs")
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(target_emacs_dir, dest, symlinks=True)
        print(f"Backed up {target_emacs_dir} -> {dest}")
    if os.path.exists(vanilla_emacs_dir):
        dest = os.path.join(backup_dir, "emacs-vanilla")
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(vanilla_emacs_dir, dest, symlinks=True)
        print(f"Backed up {vanilla_emacs_dir} -> {dest}")

    print(f"=== Phase 2: Promoting MyEmacs repo to {target_emacs_dir} ===")
    if os.path.exists(target_emacs_dir) or os.path.islink(target_emacs_dir):
        if os.path.islink(target_emacs_dir):
            os.unlink(target_emacs_dir)
        else:
            shutil.rmtree(target_emacs_dir)
    if os.path.exists(vanilla_emacs_dir) or os.path.islink(vanilla_emacs_dir):
        if os.path.islink(vanilla_emacs_dir):
            os.unlink(vanilla_emacs_dir)
        else:
            shutil.rmtree(vanilla_emacs_dir)

    os.makedirs(target_emacs_dir, exist_ok=True)
    # Copy repo items into target_emacs_dir
    for item in os.listdir(repo_dir):
        if item in [".git"]:
            continue
        src = os.path.join(repo_dir, item)
        dst = os.path.join(target_emacs_dir, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
        else:
            shutil.copy2(src, dst)
    print(f"Copied {repo_dir} contents -> {target_emacs_dir}")

    print("=== Phase 3: Cleaning Legacy Doom Caches ===")
    if os.path.exists(doom_dir):
        shutil.rmtree(doom_dir)
        print(f"Removed {doom_dir}")
    if os.path.exists(local_share_doom):
        shutil.rmtree(local_share_doom)
        print(f"Removed {local_share_doom}")
    if os.path.exists(emacs_d) or os.path.islink(emacs_d):
        if os.path.islink(emacs_d):
            os.unlink(emacs_d)
        else:
            shutil.rmtree(emacs_d)
        print(f"Removed {emacs_d}")

    print("=== Migration Script Completed Successfully ===")

if __name__ == "__main__":
    run()
