from typing import List


def distance(j: int, k: int) -> int:
    assert j <= k
    return k - j + 1


def progress_right(boxes, left, right):
    n = len(boxes)

    any_upwards_steps = False
    any_downwards_steps = False
    while right < n - 1:
        if boxes[right] >= boxes[right + 1]:
            any_downwards_steps |= boxes[right] > boxes[right + 1]
            right += 1
        else:
            if any_downwards_steps:
                break
            else:
                any_upwards_steps |= boxes[right] < boxes[min(right + 1, n - 1)]
                right += 1

    found_peak = any_upwards_steps and any_downwards_steps
    return left, right, found_peak


def catchup_left(boxes, left, right):
    while boxes[left] > boxes[right]:
        left += 1

    return left, right


def solution(boxes: List[int]) -> int:
    """Essentially the problem is to find the largest window in the input array
    that satisfies a particular condition i.e. the window contains only a single peak.

    Putting the cats on the peak in the largest window that contains only one peak
    will result in the correct answer.

    We can find the largest window by initialising two pointers left and right, which
    represent the positions of the left and right cat after they have jumped down as far
    away from each other as possible.

    We perform the following iteration until the right pointer reaches the end of the list.

    First, run the progress_right() function with moves the right pointer as far as possible
    while satisfying the "one peak" constraint. This function returns whether or not a peak
    was found as its possible to start on a peak and only descend

    Secondly, we play "catch up" with the left pointer until the window between `left`
    and `right` satisfies the condition again.

    Each pointer visits each element in the input at most once which is 2n = O(n) time.
    The additional data used is just some ints and some booleans which are unrelated
    to the size of the input so this solution incurs O(1) additional memory.
    """
    n = len(boxes)
    left = 0
    right = 0

    running_maximum = 0
    while right < n - 1:

        left, right, found_peak = progress_right(boxes, left, right)
        running_maximum = max(running_maximum, distance(left, right))

        if found_peak:
            left = right
        else:
            left, right = catchup_left(boxes, left, right)

    return running_maximum


test_cases = [
    {
        'input': [8, 6, 2, 5],
        'output': 3
    },
    {
        'input': [9, 7, 7, 10, 4, 8],
        'output': 4
    },
]

if __name__ == '__main__':
    for i, tc in enumerate(test_cases):
        print('-'*20 + str(i) + '-'*20)
        output = solution(tc['input'])
        print('Output = {}'.format(output))
        assert output == tc['output'], (tc['input'], tc['output'], output)

        # The problem is symmetric so reversing the input shouldn't change the answer
        # lets test this
        output = solution(tc['input'][::-1])
        assert output == tc['output'], (tc['input'], tc['output'], output)