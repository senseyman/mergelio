import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Hand the command line to the Dart entrypoint, which the Windows and Linux
    // runners already do and this one does not. git and ssh launch the app with
    // `--askpass <prompt>` to ask for a credential; without the arguments that
    // launch opens the workspace instead of the prompt, and the command waits
    // for an answer that can never come.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
