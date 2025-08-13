import UIKit

class SettingsViewController: UIViewController {

    let saveToCameraRollLabel: UILabel = {
        let label = UILabel()
        label.text = "Save to Camera Roll"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let saveToCameraRollSwitch: UISwitch = {
        let aSwitch = UISwitch()
        aSwitch.translatesAutoresizingMaskIntoConstraints = false
        aSwitch.tag = 0
        aSwitch.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        return aSwitch
    }()

    let forceLandscapeLabel: UILabel = {
        let label = UILabel()
        label.text = "Force Landscape Start"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let forceLandscapeSwitch: UISwitch = {
        let aSwitch = UISwitch()
        aSwitch.translatesAutoresizingMaskIntoConstraints = false
        aSwitch.tag = 1
        aSwitch.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        return aSwitch
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        title = "Settings"

        setupNavigationBar()
        setupUI()

        // Load the saved settings
        saveToCameraRollSwitch.isOn = UserSettings.saveToCameraRoll
        forceLandscapeSwitch.isOn = UserSettings.forceLandscapeStart
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
    }

    private func setupUI() {
        view.addSubview(saveToCameraRollLabel)
        view.addSubview(saveToCameraRollSwitch)
        view.addSubview(forceLandscapeLabel)
        view.addSubview(forceLandscapeSwitch)

        NSLayoutConstraint.activate([
            // Save to Camera Roll constraints
            saveToCameraRollLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            saveToCameraRollLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            saveToCameraRollSwitch.leadingAnchor.constraint(equalTo: saveToCameraRollLabel.trailingAnchor, constant: 20),
            saveToCameraRollSwitch.centerYAnchor.constraint(equalTo: saveToCameraRollLabel.centerYAnchor),
            saveToCameraRollSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Force Landscape Start constraints
            forceLandscapeLabel.leadingAnchor.constraint(equalTo: saveToCameraRollLabel.leadingAnchor),
            forceLandscapeLabel.topAnchor.constraint(equalTo: saveToCameraRollLabel.bottomAnchor, constant: 30),

            forceLandscapeSwitch.leadingAnchor.constraint(equalTo: forceLandscapeLabel.trailingAnchor, constant: 20),
            forceLandscapeSwitch.centerYAnchor.constraint(equalTo: forceLandscapeLabel.centerYAnchor),
            forceLandscapeSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func switchValueChanged(_ sender: UISwitch) {
        switch sender.tag {
        case 0:
            UserSettings.saveToCameraRoll = sender.isOn
        case 1:
            UserSettings.forceLandscapeStart = sender.isOn
        default:
            break
        }
    }
}
