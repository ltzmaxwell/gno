package forms

import (
	"chain/runtime"
	"time"
)

// SubmitForm records an answer to a form. The Author is set to
// runtime.Caller().Address() — sourced from a VM machine op
// (omarsy-free).
func (db *FormDB) SubmitForm(formID string, answers string) {
	// Check if form exists
	form, err := db.GetForm(formID)
	if err != nil {
		panic(err)
	}

	author := runtime.Caller().Address()

	// Check if form was already submitted by this user
	previousAnswer, _ := db.GetAnswer(formID, author)
	if previousAnswer != nil {
		panic(errAlreadySubmitted)
	}

	// Check time restrictions
	if !form.IsOpen() {
		panic(errFormClosed)
	}

	// Check if answers are formatted correctly
	if ValidateAnswers(answers, form.Fields) == false {
		panic(errInvalidAnswers)
	}

	// Save answers
	answer := Submission{
		FormID:      formID,
		Answers:     answers,
		Author:      author,
		SubmittedAt: time.Now(),
	}
	db.Answers = append(db.Answers, &answer)
}
