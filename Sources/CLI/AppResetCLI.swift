import ArgumentParser

@main
struct AppResetCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appreset",
        abstract: "Inspect and reset macOS app permissions and data.",
        discussion: """
        appreset lists installed apps, shows what each one declares it needs, what
        privacy (TCC) permissions it has actually been granted, and its full on-disk
        footprint — then resets any of it for clean first-run testing.

        Resets move data to the Trash by default (use --permanent to delete) and ask
        for confirmation in a terminal; in scripts pass --yes. Use --dry-run to preview.

        Reading per-app privacy grants (Camera, Microphone, Contacts, …) requires this
        tool to have Full Disk Access; run `appreset doctor` to check.

        EXAMPLES
          appreset list
          appreset info com.apple.Safari
          appreset perms com.acme.MyApp
          appreset scan com.acme.MyApp
          appreset reset com.acme.MyApp --dry-run
          appreset reset com.acme.MyApp --what tcc,defaults,caches --yes
        """,
        version: AppResetCLIInfo.version,
        subcommands: [
            List.self,
            Info.self,
            Perms.self,
            Scan.self,
            Reset.self,
            Doctor.self,
            Completion.self,
        ]
    )
}
