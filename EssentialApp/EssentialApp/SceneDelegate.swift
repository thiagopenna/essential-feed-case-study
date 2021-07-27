//
//  Copyright © 2019 Essential Developer. All rights reserved.
//

import UIKit
import CoreData
import Combine
import EssentialFeed

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?
	
	private lazy var httpClient: HTTPClient = {
		URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))
	}()
	
	private lazy var store: FeedStore & FeedImageDataStore = {
		try! CoreDataFeedStore(
			storeURL: NSPersistentContainer
				.defaultDirectoryURL()
				.appendingPathComponent("feed-store.sqlite"))
	}()

	private lazy var localFeedLoader: LocalFeedLoader = {
		LocalFeedLoader(store: store, currentDate: Date.init)
	}()
    
    private lazy var baseURL = URL(string: "https://ile-api.essentialdeveloper.com/essential-feed")!

    private lazy var navigationController = UINavigationController(
        rootViewController: FeedUIComposer.feedComposedWith(
            feedLoader: makeMockFeedLoader,
            imageLoader: makeBundleImageLoader,
            selection: showNextImage))

	convenience init(httpClient: HTTPClient, store: FeedStore & FeedImageDataStore) {
		self.init()
		self.httpClient = httpClient
		self.store = store
	}
	
	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		guard let scene = (scene as? UIWindowScene) else { return }
	
        window = UIWindow(windowScene: scene)
		configureWindow()
	}
	
	func configureWindow() {
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
	}
	
	func sceneWillResignActive(_ scene: UIScene) {
		localFeedLoader.validateCache { _ in }
	}
    
    private func showComments(for image: FeedImage) {
        let url = ImageCommentsEndpoint.get(image.id).url(baseURL: baseURL)
        let comments = CommentsUIComposer.commentsComposedWith(commentsLoader: makeRemoteCommentsLoader(url: url))
        navigationController.pushViewController(comments, animated: true)
    }
    
    private func showNextImage(tappedImage image: FeedImage) {
        let imageDetail = FeedUIComposer.feedComposedWith(
            feedLoader: makeMockFeedLoader,
            imageLoader: makeBundleImageLoader,
            selection: showNextImage)
        navigationController.pushViewController(imageDetail, animated: true)
    }
    
    private func makeRemoteCommentsLoader(url: URL) -> () -> AnyPublisher<[ImageComment], Error> {
        return { [httpClient] in
            return httpClient
                .getPublisher(url: url)
                .tryMap(ImageCommentsMapper.map)
                .eraseToAnyPublisher()
        }
    }
    
    private func makeRemoteFeedLoaderWithLocalFallback() -> AnyPublisher<[FeedImage], Error> {
        let url = FeedEndpoint.get.url(baseURL: baseURL)
        
        return httpClient
            .getPublisher(url: url)
            .tryMap(FeedItemsMapper.map)
            .caching(to: localFeedLoader)
            .fallback(to: localFeedLoader.loadPublisher)
    }
    
    private func makeMockFeedLoader() -> AnyPublisher<[FeedImage], Error> {
        let index = navigationController.viewControllers.count
        let mockImage1 = FeedImage(id: UUID(),
                                  description: "Image index \(index*3-2)",
                                  location: nil,
                                  url: Bundle.main.url(forResource: "brisbane", withExtension: "jpg")!)
        
        let mockImage2 = FeedImage(id: UUID(),
                                  description: "Image index \(index*3-1)",
                                  location: nil,
                                  url: Bundle.main.url(forResource: "jedediah", withExtension: "jpg")!)
        
        let mockImage3 = FeedImage(id: UUID(),
                                  description: "Image index \(index*3)",
                                  location: nil,
                                  url: Bundle.main.url(forResource: "vejle", withExtension: "jpg")!)
        return Just([mockImage1, mockImage2, mockImage3])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    private func makeBundleImageLoader(fileUrl: URL) -> FeedImageDataLoader.Publisher {
        let bundleImageLoader = BundleFeedImageDataLoader()
        return bundleImageLoader.loadImageDataPublisher(from: fileUrl)
    }
    
    private func makeLocalImageLoaderWithRemoteFallback(url: URL) -> FeedImageDataLoader.Publisher {
        let localImageLoader = LocalFeedImageDataLoader(store: store)

        return localImageLoader
            .loadImageDataPublisher(from: url)
            .fallback(to: { [httpClient] in
                httpClient
                    .getPublisher(url: url)
                    .tryMap(FeedImageDataMapper.map)
                    .caching(to: localImageLoader, using: url)
            })
    }
}
