//
//  EmptyMapCardView.swift
//  MapMyFriends
//

import UIKit

/// Card over the map when there's nothing to show, so an empty map doesn't look broken:
/// no contact has an address, only some contacts are shared, or Contacts access is off.
final class EmptyMapCardView: UIView {

    /// Called when the user taps the card's button.
    var onAction: (() -> Void)?

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(configuration: .borderedProminent())

    override init(frame: CGRect) {
        super.init(frame: frame)

        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.cornerRadius = 16
        background.clipsToBounds = true
        addSubview(background)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 2)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        actionButton.configuration?.cornerStyle = .capsule
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(14, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter actionTitle: The button's title, or `nil` for no button.
    func configure(title: String, message: String, actionTitle: String?) {
        titleLabel.text = title
        messageLabel.text = message
        actionButton.configuration?.title = actionTitle
        actionButton.isHidden = actionTitle == nil
    }
}
