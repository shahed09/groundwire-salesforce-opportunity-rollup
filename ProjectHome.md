This project contains Salesforce code that uses aggregate (GROUP BY) queries to automatically calculate various opportunity totals and save them on account, contact, and household records.  Features:

  * Calculates contact and household totals based on opportunity contact roles
  * Can calculate either by fiscal year or calendar year
  * Provides a huge variety of summary totals, including number and amount of opportunities closed each year and in past 365 days, first and last close date, smallest/largest/average amount, and so on
  * Easily modified to include or exclude specific record types or opportunity types
  * Uses batch apex to support large sets of data
  * Scheduled apex class can optionally update totals at night (to cover cases that are not handled by triggers)
  * Includes Visualforce "pagelets" for account or contact layout that display yearly summary totals in a compact table
  * Ideal for nonprofits tracking gifts and memberships

Some of this code depends on specific objects, fields, and helper classes that aren't all included here - it will probably require a bit of modification to fit your schema.  The purpose of the project is to share a sample framework, to allow consultants and developers to borrow and reuse our code, and to encourage others to build and share similar opportunity rollup tools.  For example, a version for use with the Nonprofit Starter Pack would be a great addition!

Please let us know if you'd like to collaborate on this, and we'll add you to the project.