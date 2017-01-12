import Quick
import Nimble
import ReactiveSwift
import Result

class PropertyEditorSpec: QuickSpec {
	override func spec() {
		describe("map(forward:backward:)") {
			var root: MutableProperty<Int>!
			var mapped: PropertyEditor<String, NoError>!

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, backward: { Int($0)! })

				expect(mapped.commitedValue) == "0"
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
				expect(mapped.commitedValue) == "1"
			}

			it("should map changes originated from the outer property") {
				mapped.try("2")
				expect(root.value) == 2
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.commitedProducer.startWithValues { mappedValues.append($0) }

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]

				mapped.try("2")

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
			}

			describe("nesting") {
				var nestedMapped: PropertyEditor<Int, NoError>!

				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var nestedMappedValues: [Int] = []

				beforeEach {
					nestedMapped = mapped.map(forward: { Int($0)! }, backward: { "\($0)" })

					root.producer.startWithValues { rootValues.append($0) }
					mapped.commitedProducer.startWithValues { mappedValues.append($0) }
					nestedMapped.commitedProducer.startWithValues { nestedMappedValues.append($0) }
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
					mapped.try("2")

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == [0, 2]

					nestedMapped.try(3)

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == [0, 2, 3]
				}
			}
		}

		describe("map(forward:attemptBackward:)") {
			var root: MutableProperty<Int>!
			var mapped: PropertyEditor<String, TestError>!
			var validationResult: FlattenedResult<String>?

			beforeEach {
				root = MutableProperty(0)
				mapped = root.map(forward: { "\($0)" }, attemptBackward: { input -> Result<Int, TestError> in
					let integer = Int(input)
					return Result(integer, failWith: TestError.default)
				})
				mapped.result.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(mapped.commitedValue) == "0"
				expect(FlattenedResult(mapped.result.value)) == FlattenedResult.success("0")
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

				expect(mapped.commitedValue) == "1"
				expect(validationResult) == .success("1")
			}

			it("should map the valid changes originated from the outer property") {
				mapped.try("2")

				expect(mapped.commitedValue) == "2"
				expect(root.value) == 2
				expect(validationResult) == .success("2")
			}

			it("should block invalid changes originated from the outer property") {
				mapped.try("😦")

				expect(mapped.commitedValue) == "0"
				expect(root.value) == 0
				expect(validationResult) == .errorDefault("😦")
			}

			it("should propagate the changes") {
				var rootValues: [Int] = []
				var mappedValues: [String] = []
				var mappedValidations: [FlattenedResult<String>] = []

				root.producer.startWithValues { rootValues.append($0) }
				mapped.commitedProducer.startWithValues { mappedValues.append($0) }
				mapped.result.signal.observeValues { result in
					mappedValidations.append(FlattenedResult(result))
				}

				root.value = 1

				expect(rootValues) == [0, 1]
				expect(mappedValues) == ["0", "1"]
				expect(mappedValidations) == [.success("1")]

				mapped.try("2")

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success("1"), .success("2")]

				mapped.try("😦")

				expect(rootValues) == [0, 1, 2]
				expect(mappedValues) == ["0", "1", "2"]
				expect(mappedValidations) == [.success("1"), .success("2"), .errorDefault("😦")]
			}

			describe("nesting") {
				var nestedMapped: PropertyEditor<String, TestError>!

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
					mapped.commitedProducer.startWithValues { mappedValues.append($0) }
					nestedMapped.commitedProducer.startWithValues { nestedMappedValues.append($0) }

					mapped.result.signal.observeValues { result in
						mappedValidations.append(FlattenedResult(result))
					}

					nestedMapped.result.signal.observeValues { result in
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

				it("should let valid.commitedValues get through") {
					mapped.try("2")

					expect(rootValues) == [0, 2]
					expect(mappedValues) == ["0", "2"]
					expect(nestedMappedValues) == ["@0", "@2"]
					expect(mappedValidations) == [.success("2")]
					expect(nestedMappedValidations) == [.success("@2")]

					nestedMapped.try("@3")

					expect(rootValues) == [0, 2, 3]
					expect(mappedValues) == ["0", "2", "3"]
					expect(nestedMappedValues) == ["@0", "@2", "@3"]
					expect(mappedValidations) == [.success("2"), .success("3")]
					expect(nestedMappedValidations) == [.success("@2"), .success("@3")]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					nestedMapped.try("@🚦")

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == [.errorDefault("🚦")]
					expect(nestedMappedValidations) == [.errorDefault("@🚦")]
				}

				it("should block the validation error from proceeding") {
					nestedMapped.try("🚦")

					expect(rootValues) == [0]
					expect(mappedValues) == ["0"]
					expect(nestedMappedValues) == ["@0"]
					expect(mappedValidations) == []
					expect(nestedMappedValidations) == [.error1("🚦")]
				}
			}
		}

		describe("validate(_:)") {
			var root: MutableProperty<Int>!
			var validated: PropertyEditor<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				root = MutableProperty(0)
				validated = root.validate { input -> Result<(), TestError> in
					return Result(input >= 0 ? () : nil, failWith: TestError.default)
				}
				validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.commitedValue) == root.value
				expect(FlattenedResult(validated.result.value)) == FlattenedResult.success(0)
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

			it("should let valid.commitedValues get through") {
				validated.try(10)
				expect(root.value) == 10
				expect(validated.commitedValue) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid.commitedValues") {
				validated.try(-10)
				expect(root.value) == 0
				expect(validated.commitedValue) == 0

				expect(validationResult) == .errorDefault(-10)
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.commitedValue) == -10
				expect(validationResult) == .errorDefault(-10)
			}

			describe("nesting") {
				var nestedValidated: PropertyEditor<Int, TestError>!

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
					validated.commitedSignal.observeValues { validatedValues.append($0) }
					nestedValidated.commitedSignal.observeValues { nestedValidatedValues.append($0) }

					validated.result.signal.observeValues { result in
						validations.append(FlattenedResult(result))
					}

					nestedValidated.result.signal.observeValues { result in
						nestedValidations.append(FlattenedResult(result))
					}

					expect(validated.commitedValue) == 0
					expect(nestedValidated.commitedValue) == 0
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

					expect(validated.commitedValue) == 1
					expect(nestedValidated.commitedValue) == 1

					expect(validatedValues) == [1]
					expect(nestedValidatedValues) == [1]

					expect(validations) == [.success(1)]
					expect(nestedValidations) == [.error1(1)]

					root.value = -1

					expect(validated.commitedValue) == -1
					expect(nestedValidated.commitedValue) == -1

					expect(validatedValues) == [1, -1]
					expect(nestedValidatedValues) == [1, -1]

					expect(validations) == [.success(1), .errorDefault(-1)]
					expect(nestedValidations) == [.error1(1), .errorDefault(-1)]

					root.value = 101

					expect(validated.commitedValue) == 101
					expect(nestedValidated.commitedValue) == 101

					expect(validatedValues) == [1, -1, 101]
					expect(nestedValidatedValues) == [1, -1, 101]

					expect(validations) == [.success(1), .errorDefault(-1), .success(101)]
					expect(nestedValidations) == [.error1(1), .errorDefault(-1), .success(101)]
				}

				it("should let valid.commitedValues get through") {
					validated.try(100)

					expect(rootValues) == [100]
					expect(validatedValues) == [100]
					expect(nestedValidatedValues) == [100]
					expect(validations) == [.success(100)]
					expect(nestedValidations) == [.success(100)]

					nestedValidated.try(200)

					expect(rootValues) == [100, 200]
					expect(validatedValues) == [100, 200]
					expect(nestedValidatedValues) == [100, 200]
					expect(validations) == [.success(100), .success(200)]
					expect(nestedValidations) == [.success(100), .success(200)]
				}

				it("should block the validation error from proceeding") {
					nestedValidated.try(-50)

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == []
					expect(nestedValidations) == [.error1(-50)]
				}

				it("should propagate the validation error back to the outer property in the middle of the chain") {
					validated.try(-100)

					expect(rootValues) == []
					expect(validatedValues) == []
					expect(nestedValidatedValues) == []
					expect(validations) == [.errorDefault(-100)]
					expect(nestedValidations) == [.errorDefault(-100)]
				}
			}
		}

		describe("validate(with:_:)") {
			describe("a MutablePropertyProtocol dependency") {
				var other: MutableProperty<String>!
				var root: MutableProperty<Int>!
				var validated: PropertyEditor<Int, TestError>!
				var validationResult: FlattenedResult<Int>?

				beforeEach {
					other = MutableProperty("")
					root = MutableProperty(0)
					validated = root.validate(with: other) { input, otherInput -> Result<(), TestError> in
						return Result(input >= 0 && otherInput == "🎃" ? () : nil, failWith: TestError.default)
					}
					validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

					expect(validated.commitedValue) == root.value
					expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
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

				it("should let valid.commitedValues get through") {
					other.value = "🎃"

					validated.try(10)
					expect(root.value) == 10
					expect(validated.commitedValue) == 10

					expect(validationResult) == .success(10)
				}

				it("should block invalid.commitedValues") {
					validated.try(-10)
					expect(root.value) == 0
					expect(validated.commitedValue) == 0

					expect(validationResult) == .errorDefault(-10)
				}

				it("should validates values originated from the root") {
					root.value = -10
					expect(validated.commitedValue) == -10
					expect(validationResult) == .errorDefault(-10)
				}

				it("should automatically revalidate the latest failed.commitedValue if the dependency changes") {
					validated.try(10)
					expect(root.value) == 0
					expect(validated.commitedValue) == 0

					expect(validationResult) == .errorDefault(10)

					other.value = "🎃"

					expect(root.value) == 10
					expect(validated.commitedValue) == 10
					expect(validationResult) == .success(10)
				}

				describe("nesting") {
					var nestedOther: MutableProperty<String>!
					var nestedValidated: PropertyEditor<Int, TestError>!

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
						validated.commitedSignal.observeValues { validatedValues.append($0) }
						nestedValidated.commitedSignal.observeValues { nestedValidatedValues.append($0) }

						validated.result.signal.observeValues { result in
							validations.append(FlattenedResult(result))
						}

						nestedValidated.result.signal.observeValues { result in
							nestedValidations.append(FlattenedResult(result))
						}

						expect(nestedValidated.commitedValue) == 0
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

						expect(validated.commitedValue) == 1
						expect(nestedValidated.commitedValue) == 1

						expect(validatedValues) == [1]
						expect(nestedValidatedValues) == [1]

						expect(validations) == [.errorDefault(1)]
						expect(nestedValidations) == [.errorDefault(1)]
					}

					it("should let valid.commitedValues get through") {
						other.value = "🎃"

						expect(rootValues) == [0]
						expect(validatedValues) == [0]
						expect(nestedValidatedValues) == [0]
						expect(validations) == [.success(0)]
						expect(nestedValidations) == [.error1(0)]

						validated.try(70)

						expect(rootValues) == [0, 70]
						expect(validatedValues) == [0, 70]
						expect(nestedValidatedValues) == [0, 70]
						expect(validations) == [.success(0), .success(70)]
						expect(nestedValidations) == [.error1(0), .error1(70)]

						nestedOther.value = "🙈"

						expect(rootValues) == [0, 70]
						expect(validatedValues) == [0, 70]
						expect(nestedValidatedValues) == [0, 70]
						expect(validations) == [.success(0), .success(70)]
						expect(nestedValidations) == [.error1(0), .error1(70), .error1(70)]

						nestedValidated.try(200)

						expect(rootValues) == [0, 70, 200]
						expect(validatedValues) == [0, 70, 200]
						expect(nestedValidatedValues) == [0, 70, 200]
						expect(validations) == [.success(0), .success(70), .success(200)]
						expect(nestedValidations) == [.error1(0), .error1(70), .error1(70), .success(200)]
					}

					it("should block the validation error from proceeding") {
						nestedValidated.try(-50)

						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == []
						expect(nestedValidations) == [.error1(-50)]
					}

					it("should propagate the validation error back to the outer property in the middle of the chain") {
						validated.try(-100)

						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == [.errorDefault(-100)]
						expect(nestedValidations) == [.errorDefault(-100)]
					}

					it("should propagate the validation error back to the outer property in the middle of the chain") {
						nestedOther.value = "🙈"

						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == []
						expect(nestedValidations) == [.error1(0)]
						
						nestedValidated.try(-100)
						
						expect(rootValues) == []
						expect(validatedValues) == []
						expect(nestedValidatedValues) == []
						expect(validations) == [.errorDefault(-100)]
						expect(nestedValidations) == [.error1(0), .errorDefault(-100)]
					}
				}
			}
		}

		describe("a PropertyEditor dependency") {
			var other: PropertyEditor<String, TestError>!
			var root: MutableProperty<Int>!
			var validated: PropertyEditor<Int, TestError>!
			var validationResult: FlattenedResult<Int>?

			beforeEach {
				other = MutableProperty("").validate { input -> Result<(), TestError> in
					return input.hasSuffix("🎃") && input != "🎃" ? .success() : .failure(TestError.error2)
				}

				root = MutableProperty(0)
				validated = root.validate(with: other) { input, otherInput -> Result<(), TestError> in
					return Result(input >= 0 && otherInput.hasSuffix("🎃") ? () : nil, failWith: TestError.default)
				}
				validated.result.signal.observeValues { validationResult = FlattenedResult($0) }

				expect(validated.commitedValue) == root.value
				expect(FlattenedResult(validated.result.value)) == FlattenedResult.errorDefault(0)
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

			it("should let valid.commitedValues get through") {
				other.try("🎃")

				validated.try(10)
				expect(root.value) == 10
				expect(validated.commitedValue) == 10

				expect(validationResult) == .success(10)
			}

			it("should block invalid.commitedValues") {
				validated.try(-10)
				expect(root.value) == 0
				expect(validated.commitedValue) == 0

				expect(validationResult) == .errorDefault(-10)
			}

			it("should validates values originated from the root") {
				root.value = -10
				expect(validated.commitedValue) == -10
				expect(validationResult) == .errorDefault(-10)
			}

			it("should automatically revalidate the latest failed.commitedValue if the dependency changes") {
				validated.try(10)
				expect(root.value) == 0
				expect(validated.commitedValue) == 0

				expect(validationResult) == .errorDefault(10)

				other.try("🎃")

				expect(root.value) == 10
				expect(validated.commitedValue) == 10
				expect(validationResult) == .success(10)
			}

			it("should automatically revalidate the latest failed.commitedValue whenever the dependency has been proposed a new input") {
				validated.try(10)
				expect(root.value) == 0
				expect(validated.commitedValue) == 0

				expect(validationResult) == .errorDefault(10)

				other.try("🎃")
				expect(other.commitedValue) == ""
				expect(FlattenedResult(other.result.value)) == FlattenedResult.error2("🎃")

				expect(root.value) == 10
				expect(validated.commitedValue) == 10
				expect(validationResult) == .success(10)

				other.try("👻🎃")
				expect(other.commitedValue) == "👻🎃"
				expect(FlattenedResult(other.result.value)) == FlattenedResult.success("👻🎃")

				expect(root.value) == 10
				expect(validated.commitedValue) == 10
				expect(validationResult) == .success(10)
			}
		}
	}
}

private enum FlattenedResult<Value: Equatable>: Equatable {
	case errorDefault(Value)
	case error1(Value)
	case error2(Value)
	case success(Value)

	init(_ result: ValidationResult<Value, TestError>) {
		switch result {
		case let .success(value):
			self = .success(value)

		case let .failure(value, error):
			switch error {
			case .default:
				self = .errorDefault(value)
			case .error1:
				self = .error1(value)
			case .error2:
				self = .error2(value)
			}
		}
	}

	static func ==(left: FlattenedResult<Value>, right: FlattenedResult<Value>) -> Bool {
		switch (left, right) {
		case (let .errorDefault(lhsValue), let .errorDefault(rhsValue)):
			return lhsValue == rhsValue
		case (let .error1(lhsValue), let .error1(rhsValue)):
			return lhsValue == rhsValue
		case (let .error2(lhsValue), let .error2(rhsValue)):
			return lhsValue == rhsValue
		case (let .success(lhsValue), let .success(rhsValue)):
			return lhsValue == rhsValue
		default:
			return false
		}
	}
}
