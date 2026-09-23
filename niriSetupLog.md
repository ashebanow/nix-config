Q1 yes. yuzu is the only niri machine for now, we may have more via VMs, new HW, etc later. It also needs to support gnome as a fallback, thats the both I was referring to.

Q2 The DMS packaged flake. I have heard people can run into issues with using the unstable version since it lags.

Q3 keep gdm, but let's give it a theme that fits my preferred gruvbox theming (note I only want a GDM theme, I want dank to manage my logged in gtk theme)

Q4 enableVPN is the only one which isn't a definite yes. Is it just a vpn status widget, or do they actually install vpn client software? If the latter, definitely no.

Q5 b for niri/dms, but the lower level gtk etc can be deleted entirely and managed by nix/dms

Q6 agree. My plan is to pull whatever I need out of the existing niri/dms config files and reapply in the nix version, then delete the old stuff

Q7 agree

Q9 agree

Q9 we are not on yuzu via ssh. we are on yuzu itself in gnome right now.

Q10 In Q5 I was talking about what to do now, and in Q6 I was discussing future moves. What I meant for Q5 was that nix should manage the new config, and that the old files should be kept in chezmoi with the .bak name and .chezmoignore

Q11 agree

Q12 agree

Q13 agree

Q14 agree

Q15 agree

Q16 agree

Q17 so this monitor is actually a 4K monitor, I don't know why nixos is detecting it as a 1080p. I'd actually like to use it with full res and a 150% scaling factor.

Q18 agreed

Q19 as I mentioned earlier, lower level stuff can be deleted entirely and managed by nix/dms. Same goes for hyprland config - its been obsoleted for lua now anyhow.
:w
Q20 agree

Q21 agree

Q22 TESmart HDK202-M24, 8K dual monitor kvm, does edid emulation but IDK if it has a "mode switch" feature. I don't think it does. Web page is at https://www.tesmart.com/products/hdk202-m24

I think as far as resolution goes, maybe using 3840x2160 at maximum refresh rate supported by the monitor would be better. 120% or 125% scale factor, whichever is closer to an integral pixel ratio.

pi --session 01a0cf45-6227-75da-9155-bdbf5c31c563
