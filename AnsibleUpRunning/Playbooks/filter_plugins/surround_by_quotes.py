"""surround_by_quotes: Ansible plugin for quoting strings."""

__author__ = 'Ruben Ricaurte <ricaurtef@gmail.com>'


def surround_by_quotes(lst: list):
    """Quotes the elements of a given list (lst)."""
    return [f'{item!r}' for item in lst]


class FilterModule:
    def filters(self):
        """Quoting filter."""
        return {'surround_by_quotes': surround_by_quotes}
