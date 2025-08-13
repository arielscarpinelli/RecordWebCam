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
        aSwitch.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        return aSwitch
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        title = "Settings"

        setupNavigationBar()
        setupUI()

        // Load the saved setting
        saveToCameraRollSwitch.isOn = UserSettings.saveToCameraRoll
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
    }

    private func setupUI() {
        view.addSubview(saveToCameraRollLabel)
        view.addSubview(saveToCameraRollSwitch)

        NSLayoutConstraint.activate([
            saveToCameraRollLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            saveToCameraRollLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            saveToCameraRollSwitch.leadingAnchor.constraint(equalTo: saveToCameraRollLabel.trailingAnchor, constant: 20),
            saveToCameraRollSwitch.centerYAnchor.constraint(equalTo: saveToCameraRollLabel.centerYAnchor),
            saveToCameraRollSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func switchValueChanged(_ sender: UISwitch) {
        UserSettings.saveToCameraRoll = sender.isOn
    }
}
