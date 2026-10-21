//
//  PhotoPinTests.swift
//  MapMyFriendsTests
//
//  Contacts with a photo get `ContactPhotoAnnotationView`, which draws the photo itself.
//  `MKMarkerAnnotationView` can't do this: it renders `glyphImage` as a one-colour
//  template, so a photo came out as a plain white disc.
//

import CoreLocation
import MapKit
import Testing
import UIKit
@testable import MapMyFriends

// MARK: - Helpers

/// PNG data for a solid-colour square, standing in for a contact photo.
private func photoData(_ color: UIColor, size: CGFloat = 60) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).pngData { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
}

private func makeAnnotation(id: String = "1", photo: Data? = nil) -> ContactAnnotation {
    ContactAnnotation(mappedContact: MappedContact(
        contactID: id,
        fullName: "Test User",
        addressLabel: "Home",
        addressString: "1 Test St",
        coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        thumbnailImageData: photo,
        phoneNumber: nil
    ))
}

/// RGBA of the pixel at `point` (in points, top-left origin) of `image`.
private func pixel(of image: UIImage, at point: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard let cgImage = image.cgImage else { return nil }
    let width = cgImage.width, height = cgImage.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Bitmap rows run top to bottom.
    let x = Int(point.x * image.scale), y = Int(point.y * image.scale)
    guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
    let i = (y * width + x) * 4
    return (CGFloat(bytes[i]) / 255, CGFloat(bytes[i + 1]) / 255, CGFloat(bytes[i + 2]) / 255, CGFloat(bytes[i + 3]) / 255)
}

/// Centre of the photo circle: horizontally centred, one radius below the top edge.
private func photoCenter(of image: UIImage) -> CGPoint {
    CGPoint(x: image.size.width / 2, y: image.size.width / 2)
}

// MARK: - Choosing a pin

struct PinChoiceTests {

    @Test func contactWithPhotoUsesPhotoPin() {
        #expect(makeAnnotation(photo: photoData(.red)).pinReuseIdentifier == ContactPhotoAnnotationView.reuseIdentifier)
    }

    @Test func contactWithoutPhotoKeepsBlueMarker() {
        #expect(makeAnnotation(photo: nil).pinReuseIdentifier == MKMapViewDefaultAnnotationViewReuseIdentifier)
    }

    @Test func undecodablePhotoKeepsBlueMarker() {
        let annotation = makeAnnotation(photo: Data([0x00, 0x01, 0x02]))

        #expect(annotation.photo == nil)
        #expect(annotation.pinReuseIdentifier == MKMapViewDefaultAnnotationViewReuseIdentifier)
    }

    @Test func photoDecodes() {
        #expect(makeAnnotation(photo: photoData(.red)).photo != nil)
    }
}

// MARK: - Drawing the photo

struct ContactPhotoPinRenderingTests {

    @Test func pinShowsThePhotoNotAWhiteDisc() throws {
        // The original bug: MKMarkerAnnotationView turned every photo into a white disc.
        let photo = try #require(UIImage(data: photoData(.red)))

        let image = ContactPhotoAnnotationView.pinImage(photo: photo)
        let center = try #require(pixel(of: image, at: photoCenter(of: image)), "Pin image is empty")

        #expect(center.r > 0.9 && center.g < 0.1 && center.b < 0.1, "Expected the photo's red, got \(center)")
    }

    @Test func photoIsClippedToACircle() throws {
        let photo = try #require(UIImage(data: photoData(.red)))

        let image = ContactPhotoAnnotationView.pinImage(photo: photo)
        let corner = try #require(pixel(of: image, at: CGPoint(x: 1, y: 1)))

        #expect(corner.a < 0.1, "The square photo's corner should be transparent, got \(corner)")
    }

    @Test func pinHasAPointerBelowThePhoto() {
        let image = ContactPhotoAnnotationView.pinImage(photo: nil)

        #expect(image.size.height > image.size.width, "Room for a pointer under the circle")
    }

    @Test func pinWithoutPhotoStillDrawsSomething() throws {
        let image = ContactPhotoAnnotationView.pinImage(photo: nil)
        let center = try #require(pixel(of: image, at: photoCenter(of: image)))

        #expect(center.a > 0.9, "A photo pin must never be invisible")
    }
}

// MARK: - The view

struct ContactPhotoAnnotationViewTests {

    private func makeView(photo: Data?) -> ContactPhotoAnnotationView {
        let view = ContactPhotoAnnotationView(annotation: nil, reuseIdentifier: ContactPhotoAnnotationView.reuseIdentifier)
        view.annotation = makeAnnotation(photo: photo)
        return view
    }

    @Test func showsThePhoto() throws {
        let view = makeView(photo: photoData(.red))
        let image = try #require(view.image)
        let center = try #require(pixel(of: image, at: photoCenter(of: image)))

        #expect(center.r > 0.9 && center.g < 0.1)
    }

    @Test func clustersWithTheBlueMarkers() {
        // Same identifier, or photo pins would never merge into clusters with everyone else.
        #expect(makeView(photo: photoData(.red)).clusteringIdentifier == ContactAnnotationView(annotation: nil, reuseIdentifier: nil).clusteringIdentifier)
    }

    @Test func hasTheSameCalloutAsTheBlueMarker() {
        let view = makeView(photo: photoData(.red))

        #expect(view.canShowCallout)
        #expect((view.rightCalloutAccessoryView as? UIButton)?.buttonType == .detailDisclosure)
    }

    @Test func pointerTipSitsOnTheCoordinate() throws {
        let view = makeView(photo: photoData(.red))
        let image = try #require(view.image)

        #expect(view.centerOffset.y == -image.size.height / 2)
    }

    @Test func reusedViewShowsTheNewContactsPhoto() throws {
        let view = makeView(photo: photoData(.red))
        view.prepareForReuse()
        view.annotation = makeAnnotation(id: "2", photo: photoData(.blue))

        let image = try #require(view.image)
        let center = try #require(pixel(of: image, at: photoCenter(of: image)))

        #expect(center.b > 0.9 && center.r < 0.1, "A reused pin kept the previous contact's photo")
    }
}

// MARK: - Live updates

struct PhotoChangeSyncTests {

    private func address(photo: Data?) -> ContactsManager.RawContactAddress {
        ContactsManager.RawContactAddress(
            contactID: "1", fullName: "Test User", addressLabel: "Home",
            addressString: "1 Test St", thumbnailImageData: photo, phoneNumber: nil
        )
    }

    @Test func changedPhotoReplacesThePin() {
        let result = ContactDiffer.diff(
            newAddresses: [address(photo: photoData(.blue))],
            existing: [makeAnnotation(photo: photoData(.red)).mappedContact]
        )

        #expect(result.toRemoveIndices == [0], "The pin kept showing the old photo")
        #expect(result.toAdd.count == 1)
    }

    @Test func addedPhotoReplacesTheBlueMarker() {
        let result = ContactDiffer.diff(
            newAddresses: [address(photo: photoData(.red))],
            existing: [makeAnnotation(photo: nil).mappedContact]
        )

        #expect(result.toRemoveIndices == [0])
    }

    @Test func unchangedPhotoLeavesThePinAlone() {
        let data = photoData(.red)
        let result = ContactDiffer.diff(
            newAddresses: [address(photo: data)],
            existing: [makeAnnotation(photo: data).mappedContact]
        )

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.isEmpty)
    }
}
