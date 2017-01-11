import Quick
import Nimble
import ReactiveSwift
import Result

class TransactionalPropertySpec: QuickSpec {
	override func spec() {
		describe("map(forward:backward:)") {
			var root: MutableProperty<Int>!
			var mapped: TransactionalProperty<String, NoError>!

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, backward: { Int($0)! })

				expect(mapped.value) == "0"
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				mapped = nil
				expect(weakRoot).to(beNil())
			}

			it("should map changes originated from the inner property") {
				root.value = 1
				expect(mapped.value) == "1"
			}

			it("should map changes originated from the outer property") {
				mapped.value = "2"
				expect(root.value) == 2
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.producer.startWithValues { mappedValues.append($0) }

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]

				mapped.value = "2"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
			}

			describe("nesting") {
				var nestedMapped: TransactionalProperty<Int, NoError>!

				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var nestedMappedValues: [Int] = []

				beforeEach {
					nestedMapped = mapped.map(forward: { Int($0)! }, backward: { "\($0)" })

					root.producer.startWithValues { rootValues.append($0) }
					mapped.producer.startWithValues { mappedValues.append($0) }
					nestedMapped.producer.startWithValues { nestedMappedValues.append($0) }
				}

				afterEach {
					nestedMapped = nil
					rootValues = []
					mappedValues = []
					nestedMappedValues = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(rootValues) == [0, 1]
					expect(mappedValues) == ["0", "1"]
					expect(nestedMappedValues) == [0, 1]
				}

				it("should propagate writes to the root") {
					mapped.value = "2"

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == [0, 2]

					nestedMapped.value = 3

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == [0, 2, 3]
				}
			}
		}

		describe("map(forward:attemptBackward:)") {
			var root: MutableProperty<Int>!
			var mapped: TransactionalProperty<String, TestError>!
			var validationResult: FlattenedResult<String>?

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, attemptBackward: { input -> Result<Int, TestError> in
					let integer = Int(input)
					return Result(integer, failWith: TestError.default)
				})
				mapped.validations.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(mapped.value) == "0"
				expect(FlattenedResult(mapped.validations.value)) == FlattenedResult.success("0")
				expect(validationResult).to(beNil())
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				mapped = nil
				expect(weakRoot).to(beNil())

				validationResult = nil
			}

			it("should map the changes originated from the inner property") {
				root.value = 1

				expect(mapped.value) == "1"
				expect(validationResult) == .success("1")
			}

			it("should map the valid changes originated from the outer property") {
				mapped.value = "2"

				expect(mapped.value) == "2"
				expect(root.value) == 2
				expect(validationResult) == .success("2")
			}

			it("should block invalid changes originated from the outer property") {
				mapped.value = "😦"

				expect(mapped.value) == "0"
				expect(root.value) == 0
				expect(validationResult) == .errorDefault
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var mappedValidations: [FlattenedResult<String>] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.producer.startWithValues { mappedValues.append($0) }
				mapped.validations.signal.observeValues { result in
					mappedValidations.append(FlattenedResult(result))
				}

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]
				expect(mappedValidations) == [.success("1")]

				mapped.value = "2"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success("1"), .success("2")]

				mapped.value = "😦"

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success("1"), .success("2"), .errorDefault]
			}

			describe("nesting") {
				var nestedMapped: TransactionalProperty<String, TestError>!

				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var mappedValidations: [FlattenedResult<String>] = []
				var nestedMappedValues: [String] = []
				var nestedMappedValidations: [FlattenedResult<String>] = []

				beforeEach {
					// Int <-> String <-> String
					nestedMapped = mapped.map(forward: { "@\($0)" }, attemptBackward: { input -> Result<String, TestError> in
						if let range = input.range(of: "@") {
							return .success(input.substring(with: range.upperBound ..< input.endIndex))
						} else {
							return .failure(TestError.error1)
						}
					})

					root.producer.startWithValues { rootValues.append($0) }
					mapped.producer.startWithValues { mappedValues.append($0) }
					nestedMapped.producer.startWithValues { nestedMappedValues.append($0) }

					mapped.validations.signal.observeValues { result in
						mappedValidations.append(FlattenedResult(result))
					}

					nestedMapped.validations.signal.observeValues { result in
						nestedMappedValidations.append(FlattenedResult(result))
					}
				}

				afterEach {
					nestedMapped = nil

					rootValues = []
					mappedValues = []
					mappedValidations = []
					nestedMappedValues = []
					nestedMappedValidations = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(rootValues) == [0, 1]
					expect(mappedValues) == ["0", "1"]
					expect(nestedMappedValues) == ["@0", "@1"]
					expect(mappedValidations) == [.success("1")]
					expect(nestedMappedValidations) == [.success("@1")]
				}

				it("should let valid values get through") {
					mapped.value = "2"

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == ["@0", "@2"]
					expect(mappedValidations) == [.success("2")]
					expect(nestedMappedValidations) == [.success("@2")]

					nestedMapped.value = "@3"

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == ["@0", "@2", "@3"]
					expect(mappedValidations) == [.success("2"), .success("3")]
					expect(nestedMappedValidations) == [.success("@2"), .success("@3")]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					nestedMapped.value = "@🚦"

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == [.errorDefault]
					expect(nestedMappedValidations) == [.errorDefault]
				}

				it("should block the validation error from proceeding") {
					nestedMapped.value = "🚦"

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == []
					expect(nestedMappedValidations) == [.error1]
				}
			}
		}

		describe("validate(_:)") {
			var root: MutableProperty<Int>!
			var validated: TransactionalProperty<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				root = MutableProperty(0)
				validated = root.validate { input -> Result<(), TestError> in
					return Result(input >= 0 ? () : nil, failWith: TestError.default)
				}
				validated.validations.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.value) == root.value
				expect(FlattenedResult(validated.validations.value)) == FlattenedResult.success(0)
				expect(validationResult).to(beNil())
			}

			afterEach {
				weak var weakRoot = root
				expect(weakRoot).toNot(beNil())

				root = nil
				expect(weakRoot).toNot(beNil())

				validated = nil
				expect(weakRoot).to(beNil())

				validationResult = nil
			}

			it("should let valid values get through") {
				validated.value = 10
				expect(root.value) == 10
				expect(validated.value) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid values") {
				validated.value = -10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(validationResult) == .errorDefault
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.value) == -10
				expect(validationResult) == .errorDefault
			}

			describe("nesting") {
				var nestedValidated: TransactionalProperty<Int, TestError>!

				var rootValues: [Int] = []
				var validatedValues: [Int] = []
				var validations: [FlattenedResult<Int>] = []
				var nestedValidatedValues: [Int] = []
				var nestedValidations: [FlattenedResult<Int>] = []

				beforeEach {
					// `validated` blocks negative values. Here we gonna block values in
					// [-99, 99]. So the effective valid range would be [100, inf).
					nestedValidated = validated.validate { input -> Result<(), TestError> in
						return abs(input) >= 100 ? .success(()) : .failure(TestError.error1)
					}

					root.signal.observeValues { rootValues.append($0) }
					validated.signal.observeValues { validatedValues.append($0) }
					nestedValidated.signal.observeValues { nestedValidatedValues.append($0) }

					validated.validations.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.validations.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(validated.value) == 0
					expect(nestedValidated.value) == 0
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
				}

				afterEach {
					nestedValidated = nil

					rootValues = []
					validatedValues = []
					validations = []
					nestedValidatedValues = []
					nestedValidations = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(validated.value) == 1
					expect(nestedValidated.value) == 1

					expect(validatedValues) == [1]
					expect(nestedValidatedValues) == [1]

					expect(validations) == [.success(1)]
					expect(nestedValidations) == [.error1]

					root.value = -1

					expect(validated.value) == -1
					expect(nestedValidated.value) == -1

					expect(validatedValues) == [1, -1]
					expect(nestedValidatedValues) == [1, -1]

					expect(validations) == [.success(1), .errorDefault]
					expect(nestedValidations) == [.error1, .errorDefault]

					root.value = 101

					expect(validated.value) == 101
					expect(nestedValidated.value) == 101

					expect(validatedValues) == [1, -1, 101]
					expect(nestedValidatedValues) == [1, -1, 101]

					expect(validations) == [.success(1), .errorDefault, .success(101)]
					expect(nestedValidations) == [.error1, .errorDefault, .success(101)]
				}

				it("should let valid values get through") {
					validated.value = 100

					expect(rootValues) == [100]
					expect(validatedValues) == [100]
					expect(nestedValidatedValues) == [100]
					expect(validations) == [.success(100)]
					expect(nestedValidations) == [.success(100)]

					nestedValidated.value = 200

					expect(rootValues) == [100, 200]
					expect(validatedValues) == [100, 200]
					expect(nestedValidatedValues) == [100, 200]
					expect(validations) == [.success(100), .success(200)]
					expect(nestedValidations) == [.success(100), .success(200)]
				}

				it("should block the validation error from proceeding") {
					nestedValidated.value = -50

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == []
					expect(nestedValidations) == [.error1]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					validated.value = -100

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.errorDefault]
				}
			}
		}

		describe("validate(with:_:)") {
			var other: MutableProperty<String>!
			var root: MutableProperty<Int>!
			var validated: TransactionalProperty<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				other = MutableProperty("")
				root = MutableProperty(0)
				validated = root.validate(with: other) { input, otherInput -> Result<(), TestError> in
					return Result(input >= 0 && otherInput == "🎃" ? () : nil, failWith: TestError.default)
				}
				validated.validations.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.value) == root.value
				expect(FlattenedResult(validated.validations.value)) == FlattenedResult.errorDefault
				expect(validationResult).to(beNil())
			}

			afterEach {
				weak var weakRoot = root
				weak var weakOther = other
				expect(weakRoot).toNot(beNil())
				expect(weakOther).toNot(beNil())

				root = nil
				other = nil
				expect(weakRoot).toNot(beNil())
				expect(weakOther).to(beNil())

				validated = nil
				expect(weakRoot).to(beNil())

				validationResult = nil
			}

			it("should let valid values get through") {
				other.value = "🎃"

				validated.value = 10
				expect(root.value) == 10
				expect(validated.value) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid values") {
				validated.value = -10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(validationResult) == .errorDefault
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.value) == -10
				expect(validationResult) == .errorDefault
			}

			it("should automatically revalidate the latest failed value if the dependency changes") {
				validated.value = 10
				expect(root.value) == 0
				expect(validated.value) == 0

				expect(validationResult) == .errorDefault

				other.value = "🎃"

				expect(root.value) == 10
				expect(validated.value) == 10
				expect(validationResult) == .success(10)
			}

			describe("nesting") {
				var nestedOther: MutableProperty<String>!
				var nestedValidated: TransactionalProperty<Int, TestError>!

				var rootValues: [Int] = []
				var validatedValues: [Int] = []
				var validations: [FlattenedResult<Int>] = []
				var nestedValidatedValues: [Int] = []
				var nestedValidations: [FlattenedResult<Int>] = []

				beforeEach {
					nestedOther = MutableProperty("")

					// `validated` blocks negative values. Here we gonna block values in
					// [-99, 99]. So the effective valid range would be [100, inf).
					nestedValidated = validated.validate(with: nestedOther) { input, otherInput -> Result<(), TestError> in
						return abs(input) >= 100 && otherInput == "🙈" ? .success(()) : .failure(TestError.error1)
					}

					root.signal.observeValues { rootValues.append($0) }
					validated.signal.observeValues { validatedValues.append($0) }
					nestedValidated.signal.observeValues { nestedValidatedValues.append($0) }

					validated.validations.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.validations.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(nestedValidated.value) == 0
				}

				afterEach {
					nestedValidated = nil

					rootValues = []
					validatedValues = []
					validations = []
					nestedValidatedValues = []
					nestedValidations = []
				}

				it("should propagate changes originated from the root") {
					root.value = 1

					expect(validated.value) == 1
					expect(nestedValidated.value) == 1

					expect(validatedValues) == [1]
					expect(nestedValidatedValues) == [1]

					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.errorDefault]
				}

				it("should let valid values get through") {
					other.value = "🎃"

					expect(rootValues) == [0]
					expect(validatedValues) == [0]
					expect(nestedValidatedValues) == [0]
					expect(validations) == [.success(0)]
					expect(nestedValidations) == [.error1]

					validated.value = 70

					expect(rootValues) == [0, 70]
					expect(validatedValues) == [0, 70]
					expect(nestedValidatedValues) == [0, 70]
					expect(validations) == [.success(0), .success(70)]
					expect(nestedValidations) == [.error1, .error1]

					nestedOther.value = "🙈"

					expect(rootValues) == [0, 70]
					expect(validatedValues) == [0, 70]
					expect(nestedValidatedValues) == [0, 70]
					expect(validations) == [.success(0), .success(70)]
					expect(nestedValidations) == [.error1, .error1, .error1]

					nestedValidated.value = 200

					expect(rootValues) == [0, 70, 200]
					expect(validatedValues) == [0, 70, 200]
					expect(nestedValidatedValues) == [0, 70, 200]
					expect(validations) == [.success(0), .success(70), .success(200)]
					expect(nestedValidations) == [.error1, .error1, .error1, .success(200)]
				}

				it("should block the validation error from proceeding") {
					nestedValidated.value = -50

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == []
					expect(nestedValidations) == [.error1]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					validated.value = -100

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.errorDefault]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					nestedOther.value = "🙈"
					nestedValidated.value = -100

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == [.errorDefault]
					expect(nestedValidations) == [.error1, .errorDefault]
				}
			}
		}
	}
}

private enum FlattenedResult<Value: Equatable>: Equatable {
	case errorDefault
	case error1
	case error2
	case success(Value)

	init(_ result: Result<Value, TestError>) {
		switch result {
		case let .success(value):
			self = .success(value)

		case let .failure(error):
			switch error {
			case .default:
				self = .errorDefault
			case .error1:
				self = .error1
			case .error2:
				self = .error2
			}
		}
	}

	static func ==(left: FlattenedResult<Value>, right: FlattenedResult<Value>) -> Bool {
		switch (left, right) {
		case (.errorDefault, .errorDefault):
			return true
		case (.error1, .error1):
			return true
		case (.error2, .error2):
			return true
		case (let .success(lhsValue), let .success(rhsValue)):
			return lhsValue == rhsValue
		default:
			return false
		}
	}
}
