import ObserverMind

let rootArguments = Array(CommandLine.arguments.dropFirst())
if rootArguments.isEmpty || (rootArguments.count == 1 && ["--version", "-v"].contains(rootArguments[0])) {
    print(ObserverVersion.cliBanner())
} else {
    ObserverCLI.main()
}
